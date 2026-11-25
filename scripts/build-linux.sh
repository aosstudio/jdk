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

source_archive="$out/$SOURCE_ASSET"
source_tree="$out/source-$OPENJDK_SHA256"
build_dir="$out/build-$JDK_ASSET-$OPENJDK_SHA256"
work=$(mktemp -d "$out/work.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT

if [[ ! -f "$source_archive" ]]; then
    curl --fail --silent --show-error --location --retry 3 --proto '=https' --proto-redir '=https' \
        --connect-timeout 30 --max-time 600 --output "$work/source.tar.gz" "$OPENJDK_SOURCE_URL"
    printf '%s  %s\n' "$OPENJDK_SHA256" "$work/source.tar.gz" | sha256sum --check
    mv "$work/source.tar.gz" "$source_archive"
fi
printf '%s  %s\n' "$OPENJDK_SHA256" "$source_archive" | sha256sum --check

if [[ ! -d "$source_tree" ]]; then
    mkdir "$work/source"
    tar --extract --gzip --file "$source_archive" --directory "$work/source" --strip-components=1
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
    env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL make JOBS="$jobs" jdk-image docs
)

jdk_image="$build_dir/images/jdk"
docs_image="$build_dir/images/docs"
{
    printf 'OpenJDK tag: %s\nOpenJDK commit: %s\n' "$OPENJDK_TAG" "$OPENJDK_COMMIT"
    printf 'Source archive: %s\nHost libc: %s\n' "$SOURCE_ASSET" "$glibc"
    "$boot_jdk/bin/java" -version 2>&1
} > "$jdk_image/aosstudio-build-info.txt"

cp -- "$source_tree/LICENSE" "$source_tree/ASSEMBLY_EXCEPTION" "$docs_image/legal/"

tar --create --gzip --file "$work/$JDK_ASSET.tar.gz" --directory "$jdk_image" .
tar --create --gzip --file "$work/$JDK_ASSET-javadoc.tar.gz" --directory "$docs_image" .
cp -- "$source_archive" "$work/$SOURCE_ASSET"
mkdir -p "$out/dist"
mv -f "$work/$JDK_ASSET.tar.gz" "$work/$JDK_ASSET-javadoc.tar.gz" "$work/$SOURCE_ASSET" "$out/dist/"
