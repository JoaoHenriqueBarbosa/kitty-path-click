#!/bin/bash
# Builds kitty with path-click.patch as Arch packages and publishes them as a pacman
# repository in the GitHub release tagged "repo". Runs as root inside an
# archlinux:base-devel container (see .github/workflows/build.yml).
#
#   ci.sh setup     point pacman at the Omarchy stable mirror and install tools
#   ci.sh check     decide whether a build is needed (writes to $GITHUB_OUTPUT)
#   ci.sh build     build the packages and the repo database into ./out
#   ci.sh publish   upload ./out to the "repo" release
set -euo pipefail

REPO_NAME=kitty-path-click
RELEASE_TAG=repo
UPSTREAM=kovidgoyal/kitty
ARCH_PACKAGING=https://gitlab.archlinux.org/archlinux/packaging/packages/kitty.git
# The packages must link against the same library versions the target machine has.
# Omarchy pins pacman to this snapshot mirror, so the build uses it too.
MIRROR='https://stable-mirror.omarchy.org/$repo/os/$arch'
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/out"

setup() {
    echo "Server = $MIRROR" > /etc/pacman.d/mirrorlist
    # -uu also downgrades: the container image is newer than the snapshot
    pacman -Syyuu --noconfirm
    pacman -S --noconfirm --needed base-devel git github-cli pacman-contrib jq
}

# Everything that should trigger a rebuild when it changes
build_key() {
    local upstream=$1
    local base python inputs
    base=$(pacman -Si kitty | awk '/^Version/ {print $3}')
    python=$(pacman -Si python | awk '/^Version/ {print $3}')
    inputs=$(cat "$HERE/path-click.patch" "$HERE/ci.sh" | sha256sum | cut -c1-12)
    echo "kitty=$upstream mirror-kitty=$base python=$python inputs=$inputs"
}

check() {
    local upstream key prev prev_key prev_ver prev_rel rel build
    upstream=$(gh api "repos/$UPSTREAM/releases/latest" --jq .tag_name)
    upstream=${upstream#v}
    key=$(build_key "$upstream")
    prev=$(gh release download "$RELEASE_TAG" -p version.json -O - 2>/dev/null || echo '{}')
    prev_key=$(jq -r '.key // ""' <<<"$prev")
    prev_ver=$(jq -r '.version // ""' <<<"$prev")
    prev_rel=$(jq -r '.pkgrel // 0' <<<"$prev")
    # Same kitty version rebuilt (new patch, new python...): bump pkgrel so pacman upgrades
    if [[ $prev_ver == "$upstream" ]]; then rel=$((prev_rel + 1)); else rel=1; fi
    if [[ $key != "$prev_key" || ${FORCE:-false} == true ]]; then build=true; else build=false; fi
    echo "upstream: $upstream"
    echo "previous: ${prev_ver:-none}-${prev_rel} [$prev_key]"
    echo "current:  [$key]"
    echo "build:    $build"
    {
        echo "build=$build"
        echo "version=$upstream"
        echo "pkgrel=$rel"
        echo "key=$key"
    } >> "${GITHUB_OUTPUT:-/dev/stdout}"
}

build() {
    : "${VERSION:?}" "${PKGREL:?}" "${KEY:?}"
    id builder &>/dev/null || useradd -m builder
    echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder
    local work=/home/builder/work
    rm -rf "$work" "$OUT"
    mkdir -p "$OUT"
    sudo -u builder -H git clone --depth 1 "$ARCH_PACKAGING" "$work"
    install -o builder -m 644 "$HERE/path-click.patch" "$work/path-click.patch"

    cd "$work"
    local arch_ver
    arch_ver=$(sed -n 's/^pkgver=//p' PKGBUILD)
    sed -i "s/^pkgver=.*/pkgver=$VERSION/; s/^pkgrel=.*/pkgrel=$PKGREL/" PKGBUILD
    # Wrap Arch's prepare() (if any) so the patch is applied after it
    cat >> PKGBUILD <<'EOF'

# --- kitty-path-click: apply the patch on top of the upstream sources ---
if declare -F prepare >/dev/null; then
    eval "$(declare -f prepare | sed '1s/^prepare/_upstream_prepare/')"
else
    _upstream_prepare() { :; }
fi
prepare() {
    _upstream_prepare
    cd "$srcdir/$pkgbase-$pkgver"
    patch -Np1 -i "$startdir/path-click.patch"
}
EOF
    chown builder PKGBUILD
    # Arch's PKGBUILD carries checksums for its own version only. The tarball's PGP
    # signature (Kovid Goyal's key, shipped in the packaging repo) is still verified.
    if [[ $arch_ver != "$VERSION" ]]; then
        echo "Arch packages $arch_ver, building $VERSION: regenerating checksums"
        sudo -u builder -H updpkgsums
    fi
    sudo -u builder -H gpg --import keys/pgp/*.asc
    sudo -u builder -H env PACKAGER="$REPO_NAME CI <noreply@github.com>" \
        makepkg --syncdeps --noconfirm --cleanbuild

    rm -f ./*-debug-*.pkg.tar.zst
    cp ./*.pkg.tar.zst "$OUT/"
    cd "$OUT"
    repo-add "$REPO_NAME.db.tar.gz" ./*.pkg.tar.zst
    # Release assets cannot be symlinks
    for ext in db files; do
        rm -f "$REPO_NAME.$ext"
        cp "$REPO_NAME.$ext.tar.gz" "$REPO_NAME.$ext"
    done
    rm -f ./*.old
    jq -n --arg v "$VERSION" --argjson r "$PKGREL" --arg k "$KEY" \
        '{version: $v, pkgrel: $r, key: $k}' > version.json
    ls -la "$OUT"
}

publish() {
    : "${VERSION:?}" "${PKGREL:?}"
    cd "$OUT"
    local notes="Pacman repository with kitty $VERSION-$PKGREL plus path-click.patch. Built $(date -u +%F)."
    gh release view "$RELEASE_TAG" >/dev/null 2>&1 ||
        gh release create "$RELEASE_TAG" --title "pacman repository" --notes "$notes"
    local old
    old=$(gh release view "$RELEASE_TAG" --json assets --jq '.assets[].name')
    # Packages first, database last, so the database never points at a missing file
    gh release upload "$RELEASE_TAG" ./*.pkg.tar.zst --clobber
    gh release upload "$RELEASE_TAG" "$REPO_NAME".db* "$REPO_NAME".files* version.json --clobber
    local name
    while read -r name; do
        if [[ -n $name && ! -e $name ]]; then
            gh release delete-asset "$RELEASE_TAG" "$name" --yes
        fi
    done <<<"$old"
    gh release edit "$RELEASE_TAG" --notes "$notes"
}

"${1:?usage: ci.sh setup|check|build|publish}"
