TARGET := iphone:clang:latest:14.0
ARCHS = arm64
include $(THEOS)/makefiles/common.mk

TOOL_NAME = machotool

machotool_FILES = main.m
machotool_CFLAGS = -fobjc-arc
machotool_CODESIGN_FLAGS = -Sentitlements.plist
machotool_INSTALL_PATH = /usr/macOS/bin

include $(THEOS_MAKE_PATH)/tool.mk
