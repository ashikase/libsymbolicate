LIBRARY_NAME = libsymbolicate
PKG_ID = jp.ashikase.libsymbolicate

libsymbolicate_INSTALL_PATH = /usr/lib
libsymbolicate_OBJC_FILES = \
    Libraries/RegexKitLite/RegexKitLite.m \
    CRBacktrace.mm \
    CRCrashReport.mm \
    CRException.mm \
    CRStackFrame.mm \
    CRThread.mm \
    BinaryInfo.mm \
    MethodInfo.mm \
    SymbolInfo.mm \
    common.c \
    demangle.mm \
    localSymbols.mm \
    symbolicate.mm
libsymbolicate_LDFLAGS = -lbz2 -licucore
libsymbolicate_PRIVATE_FRAMEWORKS = Symbolication
ADDITIONAL_CFLAGS = -DPKG_ID=\"$(PKG_ID)\" -I Libraries

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
