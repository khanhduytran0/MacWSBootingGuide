TARGET := iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

# iOS subprojects
SUBPROJECTS += MTLSimDriverHost launchdchrootexec loadtc launchservicesd2dylib
# macOS subprojects
SUBPROJECTS += launchservicesd libmachook login TestMetalIOSurface

include $(THEOS_MAKE_PATH)/aggregate.mk
