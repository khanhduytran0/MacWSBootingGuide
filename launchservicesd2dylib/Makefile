TARGET := iphone:clang:latest:14.0
ARCHS = arm64
include $(THEOS)/makefiles/common.mk

TOOL_NAME = launchservicesd2dylib

launchservicesd2dylib_FILES = main.m
launchservicesd2dylib_CFLAGS = -fobjc-arc
launchservicesd2dylib_CODESIGN_FLAGS = -Sentitlements.plist
launchservicesd2dylib_INSTALL_PATH = /usr/macOS/bin

include $(THEOS_MAKE_PATH)/tool.mk
