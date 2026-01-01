ARCHS = arm64
include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = libmachook

libmachook_FILES = jit.m objc_hooks.c mac_hooks.m  os_variant_hooks.x \
  ControlCenter_hooks.x Metal_hooks.x QuartzCore_hooks.x metal_hooks_for_m1.x RunningBoard_hooks.x
libmachook_CFLAGS = -DFORCE_M1_DRIVER # -fobjc-arc
libmachook_FRAMEWORKS = IOKit IOSurface Metal
libmachook_LDFLAGS = -undefined dynamic_lookup
libmachook_INSTALL_PATH = /usr/macOS/lib
libmachook_CODESIGN_FLAGS = bash ../vtool_and_sign.sh -S../entitlements.plist
TARGET_CODESIGN = env PLATFORM=1

#vtool -set-build-version 1 11.0 11.0 -replace -output $(THEOS_STAGING_DIR)/$(THEOS_PACKAGE_INSTALL_PREFIX)/usr/macOS/lib/libmachook.dylib $(THEOS_STAGING_DIR)/$(THEOS_PACKAGE_INSTALL_PREFIX)/usr/macOS/lib/libmachook.dylib

include $(THEOS_MAKE_PATH)/library.mk
