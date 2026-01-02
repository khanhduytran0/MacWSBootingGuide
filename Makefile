TARGET := iphone:clang:16.5:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

# iOS subprojects
SUBPROJECTS += MTLSimDriverHost launchdchrootexec machotool
# loadtc

# macOS subprojects
SUBPROJECTS += launchservicesd libmachook login TestMetalIOSurface

# for some reason Theos doesn't clean .DS_Store sometimes
before-package::
	find . -name .DS_Store -delete

include $(THEOS_MAKE_PATH)/aggregate.mk
