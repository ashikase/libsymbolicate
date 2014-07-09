/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for parsing and symbolicating iOS crash log files.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: GPL v3 (See LICENSE file for details)
 */

#ifndef CR_COMMON_H
#define CR_COMMON_H

#ifdef __cplusplus
extern "C" {
#endif

unsigned long long unsignedLongLongFromHexString(const char* str, int len);

#ifdef __cplusplus
}
#endif

#endif

/* vim: set ft=c ff=unix sw=4 ts=4 tw=80 expandtab: */
