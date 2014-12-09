/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for symbolicating memory addresses.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: LGPL v3 (See LICENSE file for details)
 */

#include "methods.h"

#include <fcntl.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <sys/mman.h>
#include <sys/stat.h>

#import "SCMethodInfo.h"

#define RO_META     (1 << 0)
#define RW_FUTURE   (1 << 30)
#define RW_REALIZED (1 << 31)

// Declare necessary types.
// NOTE: Type information is from objc-runtime-new.h (from objc4-551.1 source).
//       Struct declarations have been altered to allow accessing only required
//       information, and to differentiate 32 and 64 bit versions.

struct objc_class {
    uint32_t isa; // Actually declared in superstruct objc_object.
    uint32_t superclass;
    uint32_t buckets; // Part of cache_t struct.
    uint16_t shiftmask; // Part of cache_t struct.
    uint16_t occupied; // Part of cache_t struct.
    uint32_t data_NEVER_USE; // class_rw/ro_t * plus custom rr/alloc flags

    #define CLASS_FAST_FLAG_MASK 3
    uint32_t data() {
        return (data_NEVER_USE & ~CLASS_FAST_FLAG_MASK);
    }
};

struct objc_class_64 {
    uint64_t isa; // Actually declared in superstruct objc_object.
    uint64_t superclass;
    uint64_t buckets; // Part of cache_t struct.
    uint32_t shiftmask; // Part of cache_t struct.
    uint32_t occupied; // Part of cache_t struct.
    uint64_t data_NEVER_USE; // class_rw/ro_t * plus custom rr/alloc flags

    #define CLASS_FAST_FLAG_MASK 3
    uint64_t data() {
        return (data_NEVER_USE & ~CLASS_FAST_FLAG_MASK);
    }
};

struct class_ro_t {
    uint32_t flags;
    uint32_t instanceStart;
    uint32_t instanceSize;
    uint32_t ivarLayout;
    uint32_t name;
    uint32_t baseMethods;
    // ...
};

struct class_ro_64_t {
    uint32_t flags;
    uint32_t instanceStart;
    uint32_t instanceSize;
    uint32_t reserved;
    uint64_t ivarLayout;
    uint64_t name;
    uint64_t baseMethods;
    // ...
};

struct method_t {
    uint32_t name;
    uint32_t types;
    uint32_t imp;
};

struct method_64_t {
    uint64_t name;
    uint64_t types;
    uint64_t imp;
};

// NOTE: The first three fields of segment_command and segment_command_64, the
//       only fields that we need for this function, are the same name and size.
//       Therefore, it is not necessary to create separate 32/64 bit versions.
static segment_command *segmentNamed(load_command *cmds, uint32_t ncmds, const char *name) {
    segment_command *segment = NULL;

    load_command *cmd = cmds;
    for (uint32_t i = 0; i < ncmds; ++i) {
        if ((cmd->cmd == LC_SEGMENT) || (cmd->cmd == LC_SEGMENT_64)) {
            segment_command *seg = reinterpret_cast<segment_command *>(cmd);
            if (strcmp(seg->segname, name) == 0) {
                segment = seg;
                break;
            }
        }

        // Prepare next command.
        cmd = reinterpret_cast<load_command *>(reinterpret_cast<uint8_t *>(cmd) + cmd->cmdsize);
    }

    return segment;
}

static section *sectionNamed32(segment_command *segment, const char *name) {
    section *section = NULL;

    struct section *sect = reinterpret_cast<struct section *>(reinterpret_cast<uint8_t *>(segment) + sizeof(segment_command));
    for (uint32_t i = 0; i < segment->nsects; ++i, ++sect) {
        if (strcmp(sect->sectname, name) == 0) {
            section = sect;
            break;
        }
    }

    return section;
}

static section_64 *sectionNamed64(segment_command_64 *segment, const char *name) {
    section_64 *section = NULL;

    struct section_64 *sect = reinterpret_cast<struct section_64 *>(reinterpret_cast<uint8_t *>(segment) + sizeof(segment_command_64));
    for (uint32_t i = 0; i < segment->nsects; ++i, ++sect) {
        if (strcmp(sect->sectname, name) == 0) {
            section = sect;
            break;
        }
    }

    return section;
}

static NSArray *methodsForMappedMemory32(uint8_t *memory) {
    NSMutableArray *methods = [NSMutableArray array];

    if (memory != NULL) {
        mach_header *header = reinterpret_cast<mach_header *>(memory);
        uint32_t ncmds = header->ncmds;

        // XXX: For normal binaries (not from shared cache), will there
        //      ever be a time where the segments are not contiguous in virtual
        //      memory space?
        load_command *cmds = reinterpret_cast<load_command *>(memory + sizeof(mach_header));

        segment_command *textSeg = segmentNamed(cmds, ncmds, "__TEXT");
        if (textSeg == NULL) {
            fprintf(stderr, "ERROR: Segment \"__TEXT\" not found.\n");
            return nil;
        }
        int32_t vmdiff_text = textSeg->vmaddr - textSeg->fileoff;

        segment_command *dataSeg = segmentNamed(cmds, ncmds, "__DATA");
        if (dataSeg == NULL) {
            fprintf(stderr, "ERROR: Segment \"__DATA\" not found.\n");
            return nil;
        }
        int32_t vmdiff_data = dataSeg->vmaddr - dataSeg->fileoff;

        section *objcClassListSect = sectionNamed32(dataSeg, "__objc_classlist__DATA");
        if (objcClassListSect == NULL) {
            // NOTE: File may not contain any Objective-C classes.
            fprintf(stderr, "INFO: Section \"__objc_classlist__DATA\" not found.\n");
            return nil;
        }

        section *objcDataSect = sectionNamed32(dataSeg, "__objc_data");
        if (objcDataSect == NULL) {
            // NOTE: File may not contain any Objective-C classes.
            fprintf(stderr, "INFO: Section \"__objc_data\" not found.\n");
            return nil;
        }

        uint32_t *classList = reinterpret_cast<uint32_t *>(memory + objcClassListSect->offset);
        const uint32_t numClasses = objcClassListSect->size / sizeof(uint32_t);
        for (uint32_t i = 0; i < numClasses; ++i) {
            objc_class *klass = reinterpret_cast<objc_class *>(memory + classList[i] - vmdiff_data);

process_class:
            class_ro_t *klass_ro = reinterpret_cast<class_ro_t *>(memory + klass->data() - vmdiff_data);

            // Confirm struct is actually class_ro_t (and not class_rw_t).
            // NOTE: A "realized" or "future" class will be class_rw_t.
            // XXX: It is assumed that these flags will only be true for
            //      dynamically created classes.
            const uint32_t flags = klass_ro->flags;
            if (!(flags & RW_REALIZED) && !(flags & RW_FUTURE)) {
                const char methodType = (flags & 1) ? '+' : '-';
                const char *className = reinterpret_cast<const char *>(memory + klass_ro->name - vmdiff_text);

                if (klass_ro->baseMethods != 0) {
                    uint32_t *baseMethods = reinterpret_cast<uint32_t *>(memory + klass_ro->baseMethods - vmdiff_data);
                    BOOL isPreoptimized = (baseMethods[0] & 3);
                    //const uint32_t entsize = baseMethods[0] & ~(uint32_t)3;
                    const uint32_t count = baseMethods[1];

                    method_t *methodEntries = reinterpret_cast<method_t *>(&baseMethods[2]);
                    for (uint32_t j = 0; j < count; ++j) {
                        const char *methodName = NULL;
                        if (isPreoptimized) {
                            methodName = reinterpret_cast<const char *>(methodEntries[j].name);
                        } else {
                            methodName = reinterpret_cast<const char *>(memory + methodEntries[j].name - vmdiff_text);
                        }
                        NSString *name = [[NSString alloc] initWithFormat:@"%c[%s %s]", methodType, className, methodName];

                        SCMethodInfo *mi = [SCMethodInfo new];
                        [mi setName:name];
                        [mi setAddress:methodEntries[j].imp];
                        [methods addObject:mi];
                        [mi release];

                        [name release];
                    }
                }
            }

            if (!(flags & RO_META)) {
                // Process meta class.
                // NOTE: This is needed for retrieving class (non-instance) methods.
                klass = reinterpret_cast<objc_class *>(memory + klass->isa - vmdiff_data);
                goto process_class;
            }
        }
    }

    return methods;
}

static NSArray *methodsForMappedMemory64(uint8_t *memory) {
    NSMutableArray *methods = [NSMutableArray array];

    if (memory != NULL) {
        mach_header_64 *header = reinterpret_cast<mach_header_64 *>(memory);
        uint32_t ncmds = header->ncmds;

        // XXX: For normal binaries (not from shared cache), will there
        //      ever be a time where the segments are not contiguous in virtual
        //      memory space?
        load_command *cmds = reinterpret_cast<load_command *>(memory + sizeof(mach_header_64));

        segment_command_64 *textSeg = reinterpret_cast<segment_command_64 *>(segmentNamed(cmds, ncmds, "__TEXT"));
        if (textSeg == NULL) {
            fprintf(stderr, "ERROR: Segment \"__TEXT\" not found.\n");
            return nil;
        }
        int64_t vmdiff_text = textSeg->vmaddr - textSeg->fileoff;

        segment_command_64 *dataSeg = reinterpret_cast<segment_command_64 *>(segmentNamed(cmds, ncmds, "__DATA"));
        if (dataSeg == NULL) {
            fprintf(stderr, "ERROR: Segment \"__DATA\" not found.\n");
            return nil;
        }
        int64_t vmdiff_data = dataSeg->vmaddr - dataSeg->fileoff;

        section_64 *objcClassListSect = sectionNamed64(dataSeg, "__objc_classlist__DATA");
        if (objcClassListSect == NULL) {
            // NOTE: File may not contain any Objective-C classes.
            fprintf(stderr, "INFO: Section \"__objc_classlist__DATA\" not found.\n");
            return nil;
        }

        section_64 *objcDataSect = sectionNamed64(dataSeg, "__objc_data");
        if (objcDataSect == NULL) {
            // NOTE: File may not contain any Objective-C classes.
            fprintf(stderr, "INFO: Section \"__objc_data\" not found.\n");
            return nil;
        }

        uint64_t *classList = reinterpret_cast<uint64_t *>(memory + objcClassListSect->offset);
        const uint64_t numClasses = objcClassListSect->size / sizeof(uint64_t);
        for (uint64_t i = 0; i < numClasses; ++i) {
            objc_class_64 *klass = reinterpret_cast<objc_class_64 *>(memory + classList[i] - vmdiff_data);

process_class:
            class_ro_64_t *klass_ro = reinterpret_cast<class_ro_64_t *>(memory + klass->data() - vmdiff_data);

            // Confirm struct is actually class_ro_t (and not class_rw_t).
            // NOTE: A "realized" or "future" class will be class_rw_t.
            // XXX: It is assumed that these flags will only be true for
            //      dynamically created classes.
            const uint32_t flags = klass_ro->flags;
            if (!(flags & RW_REALIZED) && !(flags & RW_FUTURE)) {
                const char methodType = (flags & 1) ? '+' : '-';
                const char *className = reinterpret_cast<const char *>(memory + klass_ro->name - vmdiff_text);

                if (klass_ro->baseMethods != 0) {
                    uint32_t *baseMethods = reinterpret_cast<uint32_t *>(memory + klass_ro->baseMethods - vmdiff_data);
                    BOOL isPreoptimized = (baseMethods[0] & 3);
                    //const uint32_t entsize = baseMethods[0] & ~(uint32_t)3;
                    const uint32_t count = baseMethods[1];

                    method_64_t *methodEntries = reinterpret_cast<method_64_t *>(&baseMethods[2]);
                    for (uint32_t j = 0; j < count; ++j) {
                        const char *methodName = NULL;
                        if (isPreoptimized) {
                            methodName = reinterpret_cast<const char *>(methodEntries[j].name);
                        } else {
                            methodName = reinterpret_cast<const char *>(memory + methodEntries[j].name - vmdiff_text);
                        }
                        NSString *name = [[NSString alloc] initWithFormat:@"%c[%s %s]", methodType, className, methodName];

                        SCMethodInfo *mi = [SCMethodInfo new];
                        [mi setName:name];
                        [mi setAddress:methodEntries[j].imp];
                        [methods addObject:mi];
                        [mi release];

                        [name release];
                    }
                }
            }

            if (!(flags & RO_META)) {
                // Process meta class.
                // NOTE: This is needed for retrieving class (non-instance) methods.
                klass = reinterpret_cast<objc_class_64 *>(memory + klass->isa - vmdiff_data);
                goto process_class;
            }
        }
    }

    return methods;
}

NSArray *methodsForBinaryFile(const char *filepath, cpu_type_t cputype, cpu_subtype_t cpusubtype) {
    NSArray *methods = nil;

    // Open the file.
    int fd = open(filepath, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "ERROR: Failed to open file: %s.\n", filepath);
        return nil;
    }

    // Determine the file type.
    // NOTE: Both fat and mach-o file types (and all other such types,
    //       presumably) start with a uint32_t sized "magic" type identifier.
    uint32_t magic;
    if (read(fd, &magic, sizeof(magic)) < 0) {
        fprintf(stderr, "ERROR: Failed to read magic for file: %s.\n", filepath);
        close(fd);
        return nil;
    }

    // Determine offset and length of binary to map.
    off_t offset = 0;
    size_t len = 0;
    if ((magic == FAT_MAGIC) || (magic == FAT_CIGAM)) {
        BOOL isSwapped = (magic == FAT_CIGAM);

        uint32_t nfat_arch;
        if (read(fd, &nfat_arch, sizeof(nfat_arch)) < 0) {
            fprintf(stderr, "ERROR: Failed to read number of binaries contained in fat file: %s.\n", filepath);
            close(fd);
            return nil;
        }
        if (isSwapped) {
            nfat_arch = OSSwapInt32(nfat_arch);
        }

        size_t archsSize = nfat_arch * sizeof(fat_arch);
        fat_arch *archs = reinterpret_cast<fat_arch *>(malloc(archsSize));
        if (archs != NULL) {
            if (read(fd, archs, archsSize) < 0) {
                fprintf(stderr, "ERROR: Failed to read architecture structs contained in fat file: %s.\n", filepath);
                free(archs);
                close(fd);
                return nil;
            }

            // Get offset and length of binary matching requested architecture.
            for (uint32_t i = 0; i < nfat_arch; ++i) {
                cpu_type_t type = archs[i].cputype;
                cpu_subtype_t subtype = archs[i].cpusubtype;
                if (isSwapped) {
                    type = OSSwapInt32(type);
                    subtype = OSSwapInt32(subtype);
                }

                if ((type == cputype) && (subtype == cpusubtype)) {
                    // TODO: Do we need to take the "align" member into account?
                    offset = archs[i].offset;
                    len = archs[i].size;
                    if (isSwapped) {
                        offset = OSSwapInt32(offset);
                        len = OSSwapInt32(len);
                    }
                    break;
                }
            }
            free(archs);

            if (len > 0) {
                // Read magic of contained architecture.
                // NOTE: We want to reposition the offset of the file descriptor
                //       for reading cpu type information later on.
                if (lseek(fd, offset, SEEK_SET) < 0) {
                    fprintf(stderr, "ERROR: Failed to seek to offset of contained architecture in fat file: %s.\n", filepath);
                    close(fd);
                    return nil;
                }

                if (read(fd, &magic, sizeof(magic)) < 0) {
                    fprintf(stderr, "ERROR: Failed to read magic of contained architecture in fat file: %s.\n", filepath);
                    close(fd);
                    return nil;
                }
            } else {
                fprintf(stderr, "ERROR: Requested architecture \"%u %u\" not found in fat file: %s.\n", cputype, cpusubtype, filepath);
                close(fd);
                return nil;
            }
        }
    }

    // Confirm binary is Mach-O.
    if ((magic == MH_MAGIC_64) || (magic == MH_CIGAM_64) || (magic == MH_MAGIC) || (magic == MH_CIGAM)) {
        if (len == 0) {
            // Set length to size of file.
            struct stat st;
            if (fstat(fd, &st) < 0) {
                fprintf(stderr, "ERROR: Failed to fstat() file: %s.\n", filepath);
                close(fd);
                return nil;
            }
            len = st.st_size;;
        }
    } else {
        fprintf(stderr, "ERROR: Unknown magic \"0x%x\"for binary in file: %s\n", magic, filepath);
        close(fd);
        return nil;
    }

    // Confirm binary matches the requested architecture.
    // NOTE: The first six members of 32-bit and 64-bit mach header have the
    //       same name and type.
    cpu_type_t type;
    cpu_subtype_t subtype;
    BOOL isSwapped = ((magic == MH_CIGAM) || (magic == MH_CIGAM_64));
    if ((read(fd, &type, sizeof(type)) < 0) ||
        (read(fd, &subtype, sizeof(subtype)) < 0)) {
        fprintf(stderr, "ERROR: Failed to read cpu type information of binary in file: %s.\n", filepath);
        close(fd);
        return nil;
    }
    if (isSwapped) {
        type = OSSwapInt32(type);
        subtype = OSSwapInt32(subtype);
    }
    if ((type != cputype) || (subtype != cpusubtype)) {
        fprintf(stderr, "ERROR: Requested architecture \"%u %u\" not found in file: %s.\n", cputype, cpusubtype, filepath);
        close(fd);
        return nil;
    }

    void *data = mmap(NULL, len, PROT_READ, MAP_PRIVATE, fd, offset);
    close(fd);

    if (data != MAP_FAILED) {
        // Determine if requested architecture is 32-bit or 64-bit.
        uint8_t *memory = reinterpret_cast<uint8_t *>(data);
        BOOL is32Bit = !(cputype & CPU_ARCH_ABI64);
        if (is32Bit) {
            methods = methodsForMappedMemory32(memory);
        } else {
            methods = methodsForMappedMemory64(memory);
        }

        if ([methods count] == 0) {
            fprintf(stderr, "WARNING: Unable to extract methods or no methods exist in file: %s.\n", filepath);
        }

        munmap(data, len);
    } else {
        fprintf(stderr, "ERROR: Failed to mmap file: %s.\n", filepath);
    }

    return [methods sortedArrayUsingFunction:(NSInteger (*)(id, id, void *))reversedCompareMethodInfos context:NULL];
}

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
