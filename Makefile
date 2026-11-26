include locks/openjdk.mk

BOOT_JDK ?= /usr/lib/jvm/java-21-openjdk-amd64
BUILD_JOBS ?= 4

JDK_VERSION := $(subst +,-,$(patsubst jdk-%,%,$(OPENJDK_TAG)))
JDK_ASSET := aosstudio-jdk-$(JDK_VERSION)-linux-x86_64
SOURCE_ARCHIVE := aosstudio-jdk-$(JDK_VERSION)-sources.tar.gz

export OPENJDK_TAG OPENJDK_COMMIT OPENJDK_SOURCE_URL OPENJDK_SHA256 JDK_ASSET SOURCE_ARCHIVE

.PHONY: check build verify

check:
	shellcheck scripts/build-linux.sh scripts/verify-linux.sh
	@printf '%s\n' "$$OPENJDK_COMMIT" | grep -Eq '^[0-9a-f]{40}$$'
	@printf '%s\n' "$$OPENJDK_SHA256" | grep -Eq '^[0-9a-f]{64}$$'

build:
	bash scripts/build-linux.sh "$(BOOT_JDK)" "$(BUILD_JOBS)"

verify:
	bash scripts/verify-linux.sh
