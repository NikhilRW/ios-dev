# native-sim-template-version: 3
from decimal import Decimal
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import tarfile
from tempfile import TemporaryDirectory


DEVICE_DIR = "native-sim-device"
SWIFT_DIR = "native-sim-source-packages"
ENTRIES = (
    f"{DEVICE_DIR}/Build",
    f"{DEVICE_DIR}/ModuleCache.noindex",
    f"{DEVICE_DIR}/SDKStatCaches.noindex",
    f"{DEVICE_DIR}/CompilationCache.noindex",
    f"{DEVICE_DIR}/native-sim-mtimes.json",
    SWIFT_DIR,
)


class BuildArchive(tarfile.TarFile):
    def utime(self, member, target):
        mtime = member.pax_headers.get("mtime")
        if mtime is None:
            return super().utime(member, target)
        nanoseconds = int(Decimal(mtime).scaleb(9))
        os.utime(target, ns=(nanoseconds, nanoseconds))


def output(name, value):
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
        stream.write(f"{name}={value}\n")


def aws(*args):
    return subprocess.run(
        ["aws", "--endpoint-url", os.environ["R2_CACHE_ENDPOINT"], "--region", "auto", *args],
        capture_output=True, text=True, timeout=360,
    )


def cache_key(xcode):
    repository = os.environ["R2_CACHE_SOURCE"].lower()
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*/[a-z0-9_.-]+", repository):
        raise OSError("The private checkout has no repository identity")
    sdk = subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-build-version"], text=True)
    developer_dir = subprocess.check_output(["xcode-select", "-p"], text=True)
    macos = subprocess.check_output(["sw_vers", "-productVersion"], text=True)
    architecture = subprocess.check_output(["uname", "-m"], text=True)
    compatibility = [
        repository, str(Path.cwd()), os.environ.get("SCHEME", ""),
        xcode, developer_dir, sdk, macos, architecture,
    ]
    framework = os.environ.get("R2_CACHE_FRAMEWORK", "native")
    if framework != "native":
        compatibility.append(framework)
    digest = hashlib.sha256(json.dumps(compatibility).encode()).hexdigest()
    return f"native-sim/device-v1/{digest}.tar.gz"


def filter_member(member, destination):
    path = PurePosixPath(member.name)
    name = path.as_posix()
    if path.is_absolute() or ".." in path.parts:
        raise tarfile.FilterError("Invalid build cache path")
    inside_cache = any(name == entry or name.startswith(entry + "/") for entry in ENTRIES)
    if not inside_cache and not (name == DEVICE_DIR and member.isdir()):
        raise tarfile.FilterError("Unexpected build cache path")
    try:
        return tarfile.data_filter(member, destination)
    except (tarfile.AbsoluteLinkError, tarfile.LinkOutsideDestinationError):
        # These links depend on the old runner and should be regenerated.
        return None


def restore(build, archive, bucket, key, uri):
    targets = [build / DEVICE_DIR, build / SWIFT_DIR]
    if any(path.exists() or path.is_symlink() for path in targets):
        print("Local Xcode or Swift package data already exists. Skipping R2 restore.")
        return
    head = aws("s3api", "head-object", "--bucket", bucket, "--key", key, "--output", "json")
    if head.returncode:
        if re.search(r"\b(404|Not Found|NoSuchKey)\b", head.stderr, re.IGNORECASE):
            print("No compatible device cache in R2. Building cold.")
            return
        raise OSError("R2 could not stat the cache object")
    size = json.loads(head.stdout)["ContentLength"]
    if size >= shutil.disk_usage(archive.parent).free:
        raise OSError("Insufficient disk space to download the cache")
    if aws("s3", "cp", uri, str(archive), "--only-show-errors").returncode:
        raise OSError("R2 cache download failed")

    remaining = shutil.disk_usage(build).free

    def check_member(member, destination):
        nonlocal remaining
        remaining -= member.size
        if remaining <= 0:
            raise OSError("Insufficient disk space to extract the cache")
        return filter_member(member, destination)

    with TemporaryDirectory(dir=build) as staging, BuildArchive.open(archive, "r:gz") as source:
        source.extractall(staging, filter=check_member)
        derived = Path(staging, DEVICE_DIR, "Build")
        if not derived.is_dir():
            raise OSError("Cache is missing device build data")
        for target in targets:
            extracted = Path(staging, target.name)
            if extracted.exists():
                extracted.rename(target)
    output("restored", "true")
    print(f"Restored private iPhone Xcode cache ({size / 1e9:.2f} GB).")


def save(build, archive, uri):
    if not (build / DEVICE_DIR / "Build").is_dir():
        return

    def record_mtime(member):
        mtime = (build / member.name).lstat().st_mtime_ns
        member.pax_headers["mtime"] = str(Decimal(mtime).scaleb(-9))
        return member

    with tarfile.open(archive, "w:gz", compresslevel=1) as target:
        for name in ENTRIES:
            path = build / name
            if path.exists() and not path.is_symlink():
                target.add(path, arcname=name, filter=record_mtime)
    if aws("s3", "cp", str(archive), uri, "--only-show-errors").returncode:
        raise OSError("R2 cache upload failed")
    print(f"Saved private iPhone Xcode cache ({archive.stat().st_size / 1e9:.2f} GB).")


def main():
    operation = sys.argv[1]
    endpoint = os.environ.get("R2_CACHE_ENDPOINT", "")
    bucket = os.environ.get("R2_CACHE_BUCKET", "")
    values = [endpoint, bucket, os.environ.get("AWS_ACCESS_KEY_ID"), os.environ.get("AWS_SECRET_ACCESS_KEY")]
    if not any(values):
        print("R2 credentials are unset. Skipping R2 upload or restore.")
        return
    if not all(values) or not re.fullmatch(r"https://[a-f0-9]{32}(?:\.(?:eu|fedramp))?\.r2\.cloudflarestorage\.com/?", endpoint):
        raise OSError("Configure the R2 endpoint, bucket, access key, and secret access key")
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{1,61}[a-z0-9]", bucket):
        raise OSError("Invalid R2 bucket name")
    if operation == "publish":
        ipa = Path(os.environ["NATIVE_SIM_IPA_FILE"])
        run_id = os.environ["GITHUB_RUN_ID"]
        if not run_id.isdecimal() or not ipa.is_file():
            raise OSError("Missing IPA or workflow run ID")
        key = f"native-sim/ipa/{run_id}/unsigned.ipa"
        if aws("s3", "cp", str(ipa), f"s3://{bucket}/{key}", "--only-show-errors").returncode:
            raise OSError("R2 IPA upload failed")
        print(f"Saved private IPA to R2 at {key}")
        return
    if not hasattr(tarfile, "data_filter"):
        raise OSError("Python tar extraction filters are unavailable")
    build = Path("build")
    if build.is_symlink():
        raise OSError("The build directory is a symlink")
    build.mkdir(exist_ok=True)

    if operation == "restore":
        xcode = subprocess.check_output(["xcodebuild", "-version"], text=True)
        key = cache_key(xcode)
        output("key", key)
        if int(re.match(r"Xcode (\d+)", xcode)[1]) >= 26:
            output("compilation-cache", "YES")
    else:
        key = os.environ["R2_CACHE_KEY"]
    uri = f"s3://{bucket}/{key}"
    with TemporaryDirectory(dir=os.environ["RUNNER_TEMP"]) as directory:
        archive = Path(directory, "device.tar.gz")
        if operation == "restore":
            restore(build, archive, bucket, key, uri)
        elif operation == "save":
            save(build, archive, uri)


if __name__ == "__main__":
    try:
        main()
    except (OSError, EOFError, subprocess.SubprocessError, tarfile.TarError, ValueError, KeyError, TypeError):
        print("::warning::Private R2 cache operation did not complete. Check the bucket configuration, runner disk space, and cache permissions.")
