> # Version 1.7.0
> - - -
> * NEW: Added support for symbolication of SpringBoard (and other stripped binaries) on 64-bit devices.
>     * Symbolication only works for methods, not functions (due to stripping).

- - -

> # Version 1.6.0
> - - -
> * MOD: Moved crash report parsing portion of library to a separate library, libcrashreport.

- - -

> # Version 1.5.0.1
> - - -
> * FIX: Would cause crashes when reading package details with malformed or missing data.

- - -

> # Version 1.5.0
> - - -
> * NEW: Add package details to binary images that come from a debian package (dpkg).
>     * It is possible that multiple versions of a package could contain the same binary image... other contained files, such as a configuration or data file that the binary uses, may have changed.
>     * Due to this, the package details retrieved from the symbolicating device may not be the correct details for the package on the crashing device. This can be true even if the symbolicating and crashing devices are the same... if the package is up/downgraded between the time of the crash and the time of the symbolication.
> * NEW: Add install date of package to binary images that come from a debian package (dpkg).
>     * This is only added if the device processing the log is the same device that crashed.
> * FIX: For each binary image in crash report, when symbolicating, be sure to load the exact same binary.
>     * If the exact same binary is not available on the symbolicating device, symbolication for that binary will be skipped.

- - -

> # Version 1.4.0
> - - -
> * NEW: "Binary Images" output is now separated into different sections, depending on filter type.
>     * For filter type "file", it is sectioned into "Blamable" and "Filtered", as determined by the filter file.
>     * For filter type "none", it is sectioned into "dpkg", "App Store", "Other", based upon the source of the file.
>     * For filter type "none", it is unsectioned.

- - -

> # Version 1.3.0
> - - -
> * NEW: Now adds "symbolicated" property to symbolicated files.
> * NEW: Added new "isSymbolicated" property to CRCrashReport.

- - -

> # Version 1.2.1
> - - -
> * FIX: Memory leak when parsing IPS files.

- - -

> # Version 1.2.0
> - - -
> * MOD: Added armv7 and armv7s slices.

- - -

> # Version 1.1.0
> - - -
> * MOD: The crashed process is no longer eligible for inclusion in the blame list.
>     * This is because if libsymbolicate is unable to determine blame, it is obvious that the crashed process is the most likely candidate.

- - -

> # Version 1.0.1
> - - -
> * MOD: Small speed improvement when symbolicating.
> * FIX: Updated description did not include backtrace of the exception.
> * FIX: Memory leak.

- - -

> # Version 1.0.0
> - - -
> * Initial release.
