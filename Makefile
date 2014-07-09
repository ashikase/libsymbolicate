build:
	make -f Makefile.x86_64
	make -f Makefile.armv6
	lipo -create obj/libsymbolicate.dylib obj/macosx/libsymbolicate.dylib -output libsymbolicate.dylib

clean:
	make -f Makefile.x86_64 clean
	make -f Makefile.armv6 clean

distclean:
	make -f Makefile.x86_64 distclean
	make -f Makefile.armv6 distclean
