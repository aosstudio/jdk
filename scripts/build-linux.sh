#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C.UTF-8

if [[ $(uname -s) != Linux || $(uname -m) != x86_64 ]] || ! glibc=$(getconf GNU_LIBC_VERSION); then
    printf '%s\n' 'This build requires a Linux x86-64 host with glibc.' >&2
    exit 1
fi

boot_jdk=$(realpath -m "$1")
jobs=$2
if [[ ! -x "$boot_jdk/bin/javac" || ! $jobs =~ ^[1-9][0-9]*$ ]]; then
    printf '%s\n' 'Set BOOT_JDK to an OpenJDK 21 installation and BUILD_JOBS to a positive integer.' >&2
    exit 1
fi

mkdir -p out
out=$(realpath out)
exec 9>"$out/build.lock"
flock 9

cached_source="$out/$SOURCE_ARCHIVE"
source_tree="$out/source-$OPENJDK_SHA256"
build_dir="$out/build-$JDK_ASSET-$OPENJDK_SHA256"
work=$(mktemp -d "$out/work.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT

if [[ ! -f "$cached_source" ]]; then
    curl --fail --silent --show-error --location --retry 3 --proto '=https' --proto-redir '=https' \
        --connect-timeout 30 --max-time 600 --output "$work/source.tar.gz" "$OPENJDK_SOURCE_URL"
    printf '%s  %s\n' "$OPENJDK_SHA256" "$work/source.tar.gz" | sha256sum --check
    mv "$work/source.tar.gz" "$cached_source"
fi
printf '%s  %s\n' "$OPENJDK_SHA256" "$cached_source" | sha256sum --check

if [[ ! -d "$source_tree" ]]; then
    mkdir "$work/source"
    tar --extract --gzip --file "$cached_source" --directory "$work/source" --strip-components=1
    mv -T "$work/source" "$source_tree"
fi

mkdir -p "$build_dir"
version_build=${OPENJDK_TAG##*+}
(
    cd "$build_dir"
    bash "$source_tree/configure" \
        --with-boot-jdk="$boot_jdk" \
        --with-target-bits=64 \
        --enable-headless-only \
        --disable-warnings-as-errors \
        --with-native-debug-symbols=none \
        --with-version-build="$version_build" \
        --without-version-pre \
        --without-version-opt \
        --with-vendor-name=AOSStudio
    env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL make JOBS="$jobs" jdk-image
)

jdk_image="$build_dir/images/jdk"
{
    printf 'OpenJDK tag: %s\nOpenJDK commit: %s\n' "$OPENJDK_TAG" "$OPENJDK_COMMIT"
    printf 'OpenJDK source: %s\nOpenJDK source SHA-256: %s\n' "$OPENJDK_SOURCE_URL" "$OPENJDK_SHA256"
    printf 'Host libc: %s\n' "$glibc"
    "$boot_jdk/bin/java" -version 2>&1
} > "$jdk_image/aosstudio-build-info.txt"

tar --create --gzip --file "$work/$JDK_ASSET.tar.gz" --directory "$jdk_image" .
mkdir -p "$out/dist"
mv -f "$work/$JDK_ASSET.tar.gz" "$out/dist/"
