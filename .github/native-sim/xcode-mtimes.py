# native-sim-template-version: 2
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


NATIVE_SUFFIXES = {
    ".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx", ".inc", ".m",
    ".mm", ".swift", ".metal", ".modulemap", ".pch", ".podspec", ".xcconfig",
}


def build_inputs(root, app):
    tracked = subprocess.check_output(["git", "ls-files", "-z", "--cached"], cwd=root)
    paths = {root / os.fsdecode(path) for path in tracked.split(b"\0") if path}
    for directory in {app / "ios", root / "node_modules", app / "node_modules"}:
        javascript_dependencies = directory.name == "node_modules"
        for parent, children, files in os.walk(directory):
            children[:] = [name for name in children if name not in {".git", ".cache"}]
            for name in files:
                path = Path(parent) / name
                if not javascript_dependencies or path.suffix.lower() in NATIVE_SUFFIXES:
                    paths.add(path)
    return paths


def fingerprint(path):
    with path.open("rb") as stream:
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
        return digest.hexdigest()


def source_file(root, path):
    return path.is_file() and not path.is_symlink() and path.resolve() == path and path.is_relative_to(root)


def main():
    operation, derived_data = sys.argv[1:]
    root = Path(os.environ.get("NATIVE_SIM_SOURCE_ROOT") or os.environ["GITHUB_WORKSPACE"]).resolve()
    manifest = Path(derived_data) / "native-sim-mtimes.json"
    count = 0
    if operation == "save":
        entries = {}
        for path in build_inputs(root, Path.cwd()):
            if source_file(root, path):
                entries[path.relative_to(root).as_posix()] = [path.stat().st_mtime_ns, fingerprint(path)]
        manifest.write_text(json.dumps(entries), encoding="utf-8")
        count = len(entries)
    elif operation == "restore":
        for name, (mtime, digest) in json.loads(manifest.read_text(encoding="utf-8")).items():
            path = root / name
            if source_file(root, path) and fingerprint(path) == digest:
                os.utime(path, ns=(path.stat().st_atime_ns, mtime))
                count += 1
    else:
        raise ValueError(f"Unknown timestamp operation {operation}")
    print(f"Xcode input timestamps ({operation}): {count}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"::warning::Xcode input timestamps unavailable: {error}")
