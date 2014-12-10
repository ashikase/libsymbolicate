/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for symbolicating memory addresses.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: LGPL v3 (See LICENSE file for details)
 */

#include "binary.h"

#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <sys/mman.h>
#include <sys/stat.h>

BOOL offsetAndSizeOfBinaryInFile(const char *filepath, cpu_type_t cputype, cpu_subtype_t cpusubtype, off_t *offset, size_t *size) {
    off_t offsetOfBinary = 0;
    size_t sizeOfBinary = 0;

    // Open the file.
    int fd = open(filepath, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "ERROR: Failed to open file: %s.\n", filepath);
        return NO;
    }

    // Determine the file type.
    // NOTE: Both fat and mach-o file types (and all other such types,
    //       presumably) start with a uint32_t sized "magic" type identifier.
    uint32_t magic;
    if (read(fd, &magic, sizeof(magic)) < 0) {
        fprintf(stderr, "ERROR: Failed to read magic for file: %s.\n", filepath);
        close(fd);
        return NO;
    }

    // Determine offset and size of binary to map.
    if ((magic == FAT_MAGIC) || (magic == FAT_CIGAM)) {
        BOOL isSwapped = (magic == FAT_CIGAM);

        uint32_t nfat_arch;
        if (read(fd, &nfat_arch, sizeof(nfat_arch)) < 0) {
            fprintf(stderr, "ERROR: Failed to read number of binaries contained in fat file: %s.\n", filepath);
            close(fd);
            return NO;
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
                return NO;
            }

            // Get offset and size of binary matching requested architecture.
            for (uint32_t i = 0; i < nfat_arch; ++i) {
                cpu_type_t type = archs[i].cputype;
                cpu_subtype_t subtype = archs[i].cpusubtype;
                if (isSwapped) {
                    type = OSSwapInt32(type);
                    subtype = OSSwapInt32(subtype);
                }

                if ((type == cputype) && (subtype == cpusubtype)) {
                    // TODO: Do we need to take the "align" member into account?
                    offsetOfBinary = archs[i].offset;
                    sizeOfBinary = archs[i].size;
                    if (isSwapped) {
                        offsetOfBinary = OSSwapInt32(offsetOfBinary);
                        sizeOfBinary = OSSwapInt32(sizeOfBinary);
                    }
                    break;
                }
            }
            free(archs);

            if (sizeOfBinary > 0) {
                // Read magic of contained architecture.
                // NOTE: We want to reposition the offset of the file descriptor
                //       for reading cpu type information later on.
                if (lseek(fd, offsetOfBinary, SEEK_SET) < 0) {
                    fprintf(stderr, "ERROR: Failed to seek to offset of contained architecture in fat file: %s.\n", filepath);
                    close(fd);
                    return NO;
                }

                if (read(fd, &magic, sizeof(magic)) < 0) {
                    fprintf(stderr, "ERROR: Failed to read magic of contained architecture in fat file: %s.\n", filepath);
                    close(fd);
                    return NO;
                }
            } else {
                fprintf(stderr, "ERROR: Requested architecture \"%u %u\" not found in fat file: %s.\n", cputype, cpusubtype, filepath);
                close(fd);
                return NO;
            }
        }
    }

    // Confirm binary is Mach-O.
    if ((magic == MH_MAGIC_64) || (magic == MH_CIGAM_64) || (magic == MH_MAGIC) || (magic == MH_CIGAM)) {
        if (sizeOfBinary == 0) {
            // Set size to size of file.
            struct stat st;
            if (fstat(fd, &st) < 0) {
                fprintf(stderr, "ERROR: Failed to fstat() file: %s.\n", filepath);
                close(fd);
                return NO;
            }
            sizeOfBinary = st.st_size;;
        }
    } else {
        fprintf(stderr, "ERROR: Unknown magic \"0x%x\"for binary in file: %s\n", magic, filepath);
        close(fd);
        return NO;
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
        return NO;
    }
    if (isSwapped) {
        type = OSSwapInt32(type);
        subtype = OSSwapInt32(subtype);
    }
    if ((type != cputype) || (subtype != cpusubtype)) {
        fprintf(stderr, "ERROR: Requested architecture \"%u %u\" not found in file: %s.\n", cputype, cpusubtype, filepath);
        close(fd);
        return NO;
    }

    // Clean-up.
    close(fd);

    // Output.
    if (offset != NULL) {
        *offset = offsetOfBinary;
    }
    if (size != NULL) {
        *size = sizeOfBinary;
    }

    return YES;
}

BOOL isEncrypted(const char *filepath, cpu_type_t cputype, cpu_subtype_t cpusubtype) {
    BOOL isEncrypted = NO;

    // Determine offset and size of the requested architecture in the file.
    // NOTE: File may contain multiple architectures, or incorrect architecture.
    off_t offset;
    size_t size;
    if (!offsetAndSizeOfBinaryInFile(filepath, cputype, cpusubtype, &offset, &size)) {
        fprintf(stderr, "ERROR: Failed to determine offset and size of requested architecture in file: %s.\n", filepath);
        return nil;
    }

    // Open the file.
    int fd = open(filepath, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "ERROR: Failed to open file: %s.\n", filepath);
        return nil;
    }

    // Map the binary.
    void *data = mmap(NULL, size, PROT_READ, MAP_PRIVATE, fd, offset);
    close(fd);

    // Determine encryption status.
    if (data != MAP_FAILED) {
        // Determine if requested architecture is 32-bit or 64-bit.
        BOOL is32Bit = !(cputype & CPU_ARCH_ABI64);
        size_t headerSize = (is32Bit ? sizeof(mach_header) : sizeof(mach_header_64));

        // Search for encryption info load command.
        uint8_t *memory = reinterpret_cast<uint8_t *>(data);
        mach_header *header = reinterpret_cast<mach_header *>(memory);
        uint32_t ncmds = header->ncmds;
        load_command *cmd = reinterpret_cast<load_command *>(memory + headerSize);
        for (uint32_t i = 0; i < ncmds; ++i) {
            if ((cmd->cmd == LC_ENCRYPTION_INFO) || (cmd->cmd == LC_ENCRYPTION_INFO_64)) {
                // NOTE: Both 32-bit and 64-bit encryption info structs are the
                //       same, except for padding at the end.
                encryption_info_command *enc = reinterpret_cast<encryption_info_command *>(cmd);
                isEncrypted = (enc->cryptid != 0);
                break;
            }

            // Prepare next command.
            cmd = reinterpret_cast<load_command *>(reinterpret_cast<uint8_t *>(cmd) + cmd->cmdsize);
        }

        munmap(data, size);
    } else {
        fprintf(stderr, "ERROR: Failed to mmap file: %s.\n", filepath);
    }

    return isEncrypted;
}

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
