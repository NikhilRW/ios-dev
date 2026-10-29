#!/bin/bash
set -euo pipefail



# Upterm uses a non-login shell, which may not have Homebrew on PATH yet.
if ! command -v brew >/dev/null 2>&1; then
  for BREW in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$BREW" ]; then
      eval "$("$BREW" shellenv)"
      break
    fi
  done
fi
if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required. GitHub's macOS runners include it by default." >&2
  exit 1
fi

export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
echo "Installing Neovim and LazyVim tools..."
brew install neovim git ripgrep fd lazygit fzf tree-sitter-cli
eval "$(brew shellenv)"

# Check the minimum supported LazyVim version without loading any user config.
nvim --headless -u NONE -i NONE \
  '+lua if vim.fn.has("nvim-0.11.2") == 0 then print("LazyVim requires Neovim >= 0.11.2"); vim.cmd("cquit 1") end' \
  +qa

REPO=https://github.com/NikhilRW/my-lazyvim-config.git
CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}"
CONFIG="$CONFIG_ROOT/${NVIM_APPNAME:-nvim}"
mkdir -p "$CONFIG_ROOT"

ORIGIN=""
if [ -d "$CONFIG/.git" ]; then
  ORIGIN=$(git -C "$CONFIG" remote get-url origin 2>/dev/null || true)
fi
case "$ORIGIN" in
  "$REPO"|https://github.com/NikhilRW/my-lazyvim-config|git@github.com:NikhilRW/my-lazyvim-config.git)
    echo "Your preset is already installed; keeping local edits."
    ;;
  *)
    if [ -e "$CONFIG" ] || [ -L "$CONFIG" ]; then
      BACKUP="$(mktemp -d "$CONFIG_ROOT/nvim-backup.XXXXXX")"
      mv "$CONFIG" "$BACKUP/config"
      echo "Previous config saved to $BACKUP/config"
    fi
    git clone --depth 1 --branch main "$REPO" "$CONFIG"
    ;;
esac

if [ ! -f "$CONFIG/init.lua" ]; then
  echo "The preset does not contain init.lua: $CONFIG" >&2
  exit 1
fi

# The preset sets PowerShell options after lazy.setup(). Reset them after its
# init.lua loads so plugin commands and ToggleTerm work on the cloud Mac.
if ! grep -Fq -- '-- native-sim macOS shell override' "$CONFIG/init.lua"; then
  cat >> "$CONFIG/init.lua" <<'LUA'

-- native-sim macOS shell override
if vim.fn.has("macunix") == 1 then
  vim.opt.shell = "/bin/zsh"
  vim.opt.shellcmdflag = "-c"
  vim.opt.shellquote = ""
  vim.opt.shellxquote = ""
  vim.opt.shellpipe = "2>&1| tee"
  vim.opt.shellredir = ">%s 2>&1"
end
LUA
fi

echo "Restoring plugins from your preset's lazy-lock.json..."
nvim --headless '+Lazy! restore' +qa

printf '\nReady! Config: %s\n' "$CONFIG"
printf 'Open your app: nvim "%s/ios/rn_on_cloud_ios_simulator/ContentView.swift"\n' "${GITHUB_WORKSPACE:-$PWD}"
echo 'After saving, run: native-sim-rebuild'
