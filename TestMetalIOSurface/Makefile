TARGET := macosx:clang:latest:14.0
ARCHS = arm64
include $(THEOS)/makefiles/common.mk

TOOL_NAME = TestMetalIOSurface

TestMetalIOSurface_FILES = main.m
TestMetalIOSurface_CFLAGS = -fobjc-arc
TestMetalIOSurface_CODESIGN_FLAGS = -S../entitlements.plist
TestMetalIOSurface_INSTALL_PATH = /usr/macOS/bin
TestMetalIOSurface_LDFLAGS = -F../Frameworks
TestMetalIOSurface_FRAMEWORKS = IOMobileFramebuffer

include $(THEOS_MAKE_PATH)/tool.mk
