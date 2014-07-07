LIBRARY_NAME = libsymbolicate
PKG_ID = jp.ashikase.libsymbolicate

libsymbolicate_INSTALL_PATH = /usr/lib
libsymbolicate_OBJC_FILES = \
    Libraries/RegexKitLite/RegexKitLite.m \
    Source/common.c \
    Source/crashreport/CRBacktrace.mm \
    Source/crashreport/CRCrashReport.mm \
    Source/crashreport/CRException.mm \
    Source/crashreport/CRStackFrame.mm \
    Source/crashreport/CRThread.mm \
    Source/symbolicate/BinaryInfo.mm \
    Source/symbolicate/MethodInfo.mm \
    Source/symbolicate/SymbolInfo.mm \
    Source/symbolicate/demangle.mm \
    Source/symbolicate/localSymbols.mm \
    Source/symbolicate/symbolicate.mm
libsymbolicate_LDFLAGS = -lbz2 -licucore
libsymbolicate_PRIVATE_FRAMEWORKS = Symbolication
ADDITIONAL_CFLAGS = -DPKG_ID=\"$(PKG_ID)\" -ILibraries -ISource -ISource/symbolicate

ARCHS = armv6
TARGET = iphone
TARGET_IPHONEOS_DEPLOYMENT_VERSION = 3.0

include theos/makefiles/common.mk
include $(THEOS)/makefiles/library.mk

after-stage::
	# Remove repository-related files
	- find $(THEOS_STAGING_DIR) -name '.gitkeep' -delete

distclean: clean
	- rm -f $(THEOS_PROJECT_DIR)/$(APP_ID)*.deb
	- rm -f $(THEOS_PROJECT_DIR)/.theos/packages/*
