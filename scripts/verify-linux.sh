#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C.UTF-8

out=$(realpath out)
exec 9>"$out/build.lock"
flock --shared 9

work=$(mktemp -d "$out/verify.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/jdk"

tar --extract --gzip --file "$out/dist/$JDK_ASSET.tar.gz" --directory "$work/jdk"

export JAVA_HOME="$work/jdk"
bin="$JAVA_HOME/bin"
elf=$(readelf --file-header "$bin/java")
grep -Eq 'Class:[[:space:]]+ELF64' <<< "$elf"
grep -Eq 'Machine:.*X86-64' <<< "$elf"
version=${OPENJDK_TAG#jdk-}
[[ $("$bin/javac" -version) == "javac ${version%+*}" ]]
test -s "$JAVA_HOME/lib/src.zip"
test -s "$JAVA_HOME/jmods/java.base.jmod"
test -s "$JAVA_HOME/legal/java.base/LICENSE"
test ! -e "$JAVA_HOME/lib/libawt_xawt.so"

"$bin/keytool" -list -cacerts -storepass changeit > "$work/cacerts.txt"
grep -q 'trustedCertEntry' "$work/cacerts.txt"

fixture=tests/Hello.java
"$bin/javac" --release 17 -d "$work" "$fixture"
"$bin/jar" --create --file "$work/hello.jar" --main-class Hello -C "$work" Hello.class
[[ $("$bin/java" -jar "$work/hello.jar") == 'Hello from OpenJDK' ]]

"$bin/jlink" --module-path "$JAVA_HOME/jmods" --add-modules java.base --output "$work/runtime"
[[ $("$work/runtime/bin/java" -jar "$work/hello.jar") == 'Hello from OpenJDK' ]]

"$bin/javadoc" -quiet -Xdoclint:all,-missing --no-platform-links -d "$work/javadoc" "$fixture"
test -s "$work/javadoc/Hello.html"
printf '%s\n' 'Packaged JDK verified.'
