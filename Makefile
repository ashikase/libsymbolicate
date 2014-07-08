LIBRARY_NAME = libsymbolicate
PKG_ID = jp.ashikase.libsymbolicate

libsymbolicate_INSTALL_PATH = /usr/lib
libsymbolicate_OBJC_FILES = \
    Libraries/RegexKitLite/RegexKitLite.m \
    Source/common.c \
    Source/crashreport/CRBacktrace.mm \
    Source/crashreport/CRBinaryImage.mm \
    Source/crashreport/CRCrashReport.mm \
    Source/crashreport/CRException.mm \
    Source/crashreport/CRStackFrame.mm \
    Source/crashreport/CRThread.mm \
    Source/symbolicate/SCBinaryInfo.mm \
    Source/symbolicate/SCMethodInfo.mm \
    Source/symbolicate/SCSymbolInfo.mm \
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
	# Remove repository-related files.
	- find $(THEOS_STAGING_DIR) -name '.gitkeep' -delete
	# Copy header files to include directory.
	- cp $(THEOS_PROJECT_DIR)/Source/common.h $(THEOS_STAGING_DIR)/usr/include/libsymbolicate/
	- cp $(THEOS_PROJECT_DIR)/Source/crashreport/CR*.h $(THEOS_STAGING_DIR)/usr/include/libsymbolicate/
	- cp $(THEOS_PROJECT_DIR)/Source/symbolicate/SC*.h $(THEOS_STAGING_DIR)/usr/include/libsymbolicate/
	- cp $(THEOS_PROJECT_DIR)/Source/symbolicate/demangle.h $(THEOS_STAGING_DIR)/usr/include/libsymbolicate/
	- cp $(THEOS_PROJECT_DIR)/Source/symbolicate/localSymbols.h $(THEOS_STAGING_DIR)/usr/include/libsymbolicate/
	- cp $(THEOS_PROJECT_DIR)/Source/symbolicate/symbolicate.h $(THEOS_STAGING_DIR)/usr/include/libsymbolicate/

distclean: clean
	- rm -f $(THEOS_PROJECT_DIR)/$(APP_ID)*.deb
	- rm -f $(THEOS_PROJECT_DIR)/.theos/packages/*
