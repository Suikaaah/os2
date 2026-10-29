#!/usr/bin/env bash
set -euxo pipefail

dnf config-manager setopt \
    assumeyes=1 \
    fastestmirror=1 \
    localpkg_gpgcheck=1 \
    max_parallel_downloads=16

# Repositories

# distribution-gpg-keys ships the RPM Fusion keys in the base image, so the
# release packages below can be verified without fetching a key over the wire.
rpm --import \
    /usr/share/distribution-gpg-keys/rpmfusion/RPM-GPG-KEY-rpmfusion-free-fedora-${FEDORA_VERSION} \
    /usr/share/distribution-gpg-keys/rpmfusion/RPM-GPG-KEY-rpmfusion-nonfree-fedora-${FEDORA_VERSION}

dnf install \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm

dnf copr enable alternateved/keyd
dnf copr enable scottames/ghostty

# Flathub
curl -o /etc/flatpak/remotes.d/flathub.flatpakrepo \
    https://dl.flathub.org/repo/flathub.flatpakrepo

# Packages

# The nvidia variant builds akmods against this image's kernel, so the headers
# are held at that version for the rest of the build.
dnf install kernel-devel-matched
dnf versionlock add kernel-devel-matched

# Hardware and patent-encumbered codecs.
dnf swap --allowerasing ffmpeg-free ffmpeg

packages=(
    # Desktop
    ghostty
    ibus-mozc
    xdg-terminal-exec
    # IO
    keyd
    input-remapper
    # Development
    gh
    fzf
    rustup
    opam
    neovim
    python3-neovim
    # Gaming
    steam
)

dnf install "${packages[@]}"

# Claude
tee /etc/yum.repos.d/claude-code.repo <<'EOF'
[claude-code]
name=Claude Code
baseurl=https://downloads.claude.ai/claude-code/rpm/latest
enabled=1
gpgcheck=1
gpgkey=https://downloads.claude.ai/keys/claude-code.asc
EOF
dnf install claude-code

# Tailscale
tee /etc/yum.repos.d/tailscale.repo <<'EOF'
[tailscale-stable]
name=Tailscale stable
baseurl=https://pkgs.tailscale.com/stable/fedora/$basearch
enabled=1
type=rpm
repo_gpgcheck=1
gpgcheck=1
gpgkey=https://pkgs.tailscale.com/stable/fedora/repo.gpg
EOF
dnf install tailscale
systemctl enable tailscaled

# Bitwarden CLI. There is no RPM, so this takes the standalone binary from the
# link Bitwarden redirects to its latest release. /usr/local points into /var
# on an ostree system, so the binary goes in /usr/bin to be part of the image.
bw_dir=$(mktemp -d)
curl -fsSL -o "${bw_dir}/bw.zip" \
    'https://vault.bitwarden.com/download/?app=cli&platform=linux'
unzip "${bw_dir}/bw.zip" bw -d "${bw_dir}"
install -m 0755 "${bw_dir}/bw" /usr/bin/bw
rm -rf "${bw_dir}"

# Ghostty replaces the terminal Silverblue ships. GLib picks the terminal for a
# Terminal=true desktop entry off a fixed list that names ptyxis and not
# ghostty, so xdg-terminal-exec above stands in: it is the first name on that
# list, and with ptyxis gone it falls back to the sole TerminalEmulator entry
# left. Nothing requires ptyxis, so this removes that package and nothing else.
dnf remove ptyxis

# No browser is baked in; one can be installed from Flathub instead.
dnf remove firefox

