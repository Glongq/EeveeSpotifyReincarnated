ifeq ($(NATIVE_DOWNLOADS_JAILBREAK),1)
TARGET := iphone:clang:latest:16.1
else
TARGET := iphone:clang:latest:14.0
endif
INSTALL_TARGET_PROCESSES = Spotify
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = EeveeSpotify

REPO_SLUG ?= $(shell git remote get-url origin 2>/dev/null | sed -E 's|.*github\.com[:/]([^/]+/[^/.]+)(\.git)?$$|\1|')
REPO_SLUG_FINAL := $(if $(REPO_SLUG),$(REPO_SLUG),jaydenjcpy/EeveeSpotifyReincarnated)

BRANCH_NAME ?= $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null)
BRANCH_NAME_FINAL := $(if $(BRANCH_NAME),$(BRANCH_NAME),Master)

$(shell mkdir -p Sources/EeveeSpotify/Generated)
$(shell config_tmp=$$(mktemp); printf 'enum GeneratedConfig {\n    static let repoSlug = "%s"\n    static let branchName = "%s"\n}\n' "$(REPO_SLUG_FINAL)" "$(BRANCH_NAME_FINAL)" > "$$config_tmp"; cmp -s "$$config_tmp" Sources/EeveeSpotify/Generated/RepoSlug.swift || cp "$$config_tmp" Sources/EeveeSpotify/Generated/RepoSlug.swift; rm -f "$$config_tmp")

EeveeSpotify_FILES = $(shell find Sources/EeveeSpotify -name '*.swift') $(shell find Sources/EeveeSpotifyC -name '*.m' -o -name '*.c' -o -name '*.mm' -o -name '*.cpp')
EeveeSpotify_SWIFTFLAGS = -ISources/EeveeSpotifyC/include -Osize
EeveeSpotify_EXTRA_FRAMEWORKS = EeveeSwiftProtobuf
EeveeSpotify_CFLAGS = -fobjc-arc -ISources/EeveeSpotifyC/include -Os

# Opt in explicitly: the IPA overlay still uses its original, frozen v7 sources.
ifeq ($(NATIVE_DOWNLOADS_JAILBREAK),1)
EeveeSpotify_FILES += $(wildcard NativeDownloads/src/*.m NativeDownloads/src/*.c) NativeDownloads/jailbreak/Runtime.m modules/fishhook/fishhook.c
EeveeSpotify_CFLAGS += -INativeDownloads/src -Imodules/fishhook -DSAP_ENABLE_WAV_CAPTURE=0
EeveeSpotify_SWIFTFLAGS += -D NATIVE_DOWNLOADS_JAILBREAK
EeveeSpotify_FRAMEWORKS += AudioToolbox AVFAudio AVFoundation CoreMedia CoreGraphics
endif

# RootHide's compatibility implementation of libroot resolves jailbreak paths
# through libroothide at runtime. Rootless builds continue to use libroot.
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
EeveeSpotify_SWIFTFLAGS += -D ROOTHIDE
EeveeSpotify_LDFLAGS += -lroothide -Xlinker -rpath -Xlinker @loader_path/.jbroot/Library/Frameworks
else
EeveeSpotify_LDFLAGS += -lroot
endif

# Sideload compatibility (keychain redirect, group containers, CloudKit) is
# handled out-of-process by modules/zxPluginsInject — LC-injected via ipapatch
# in build-ipa-local.sh and the GitHub workflow. No flags needed here.

include $(THEOS_MAKE_PATH)/tweak.mk

ifeq ($(NATIVE_DOWNLOADS_JAILBREAK),1)
before-package:: $(THEOS_STAGING_DIR)/DEBIAN/control
	sed -i.bak -e 's/^Name:.*/Name: EeveeSpotify (Native Downloads)/' -e 's/^Maintainer:.*/Maintainer: Glongq/' -e 's/^Description:.*/Description: Unofficial EeveeSpotify fork with native downloads, UI v7. Codex-assisted build./' $(THEOS_STAGING_DIR)/DEBIAN/control
	rm -f $(THEOS_STAGING_DIR)/DEBIAN/control.bak
	mkdir -p $(THEOS_STAGING_DIR)/usr/share/doc/com.eevee.spotify
	cp LICENSE $(THEOS_STAGING_DIR)/usr/share/doc/com.eevee.spotify/COPYING
	cp NativeDownloads/jailbreak/licenses/*.txt $(THEOS_STAGING_DIR)/usr/share/doc/com.eevee.spotify/
	# Theos optimizes plists after before-package. Normalize before signing so
	# the framework's sealed Info.plist is not changed after its signature.
	plutil -convert binary1 $(THEOS_STAGING_DIR)/Library/Frameworks/EeveeSwiftProtobuf.framework/Info.plist
	codesign --force --sign - --timestamp=none $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/EeveeSpotify.dylib
	codesign --force --sign - --timestamp=none $(THEOS_STAGING_DIR)/Library/Frameworks/EeveeSwiftProtobuf.framework
endif

internal-stage::
	# Bundle EeveeSwiftProtobuf.framework into the package. Renamed from
	# SwiftProtobuf so the @objc class names don't collide with the
	# SwiftProtobuf statically embedded in SpotifyShared.framework.
	mkdir -p $(THEOS_STAGING_DIR)/Library/Frameworks
	cp -r $(THEOS)/lib/iphone/$(or $(THEOS_PACKAGE_SCHEME),rootless)/EeveeSwiftProtobuf.framework $(THEOS_STAGING_DIR)/Library/Frameworks/
	# Compile the karaoke background Metal shader into a .metallib and
	# stage it next to the tweak binary so device.makeLibrary(filepath:)
	# can load it at runtime (Theos's tweak.mk has no built-in Metal
	# shader compilation step the way an Xcode app target's build phases
	# do, so this is done by hand here — UNTESTED, no Theos/Metal
	# toolchain was available to verify this actually produces a working
	# .metallib or that the staged path is correct; if `make package`
	# fails at this step or the shader doesn't load at runtime, check
	# this block first).
	xcrun -sdk iphoneos metal -c Sources/EeveeSpotify/Karaoke/KaraokeBackgroundShader.metal \
		-o $(THEOS_OBJ_DIR)/KaraokeBackgroundShader.air
	xcrun -sdk iphoneos metallib $(THEOS_OBJ_DIR)/KaraokeBackgroundShader.air \
		-o $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/KaraokeBackgroundShader.metallib

# Build EeveeSwiftProtobuf.framework from apple/swift-protobuf source. Run
# this once before `make package`. Re-run if SWIFTPROTOBUF_VERSION changes
# or `swift --version` jumps a major.
build-eeveeswiftprotobuf:
	Tools/SwiftProtobufBuild/build-eeveeswiftprotobuf.sh
