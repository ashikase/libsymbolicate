#ifndef SYMBOLICATE_DEMANGLE_H_
#define SYMBOLICATE_DEMANGLE_H_

#ifdef __cplusplus
extern "C" {
#endif

NSString *demangle(NSString *mangled);

#ifdef __cplusplus
}
#endif

#endif // SYMBOLICATE_DEMANGLE_H_

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
