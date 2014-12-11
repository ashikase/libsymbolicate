/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for symbolicating memory addresses.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: LGPL v3 (See LICENSE file for details)
 */

#include "localSymbols.h"

#include <fcntl.h>
#include <mach-o/nlist.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <launch-cache/dyld_cache_format.h>

uint64_t offsetOfDylibInSharedCache(const char *sharedCachePath, const char *filepath) {
    uint64_t offset = 0;

    int fd = open(sharedCachePath, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "ERROR: Failed to open shared cache file: %s\n", sharedCachePath);
        return 0;
    }

    size_t headerSize = sizeof(dyld_cache_header);
    dyld_cache_header *header = reinterpret_cast<dyld_cache_header *>(malloc(headerSize));
    if (read(fd, header, headerSize) < 0) {
        fprintf(stderr, "ERROR: Failed to read the shared cache header\n");
        free(header);
        close(fd);
        return 0;
    }
    const uint32_t imagesOffset = header->imagesOffset;
    const uint32_t imagesCount = header->imagesCount;
    const uint64_t dyldBaseAddress = header->dyldBaseAddress;
    free(header);

    // Adjust for page size.
    // NOTE: mmap() may fail if offset is not page-aligned.
    const int pagesize = getpagesize();
    const uint32_t imagesPage = imagesOffset / pagesize;
    const off_t imagesPageOffset = imagesPage * pagesize;
    const size_t imagesLen = (imagesOffset - imagesPageOffset) + (imagesCount * sizeof(dyld_cache_image_info));

    void *data = mmap(NULL, imagesLen, PROT_READ, MAP_PRIVATE, fd, imagesPageOffset);
    if (data != MAP_FAILED) {
        uint8_t *memory = reinterpret_cast<uint8_t *>(data);

        dyld_cache_image_info *images = reinterpret_cast<dyld_cache_image_info *>(memory + imagesOffset - imagesPageOffset);
        for (uint32_t i = 0; i < imagesCount; ++i) {
            // NOTE: The maximum allowed path length is 1024 bytes.
            //       (According to /usr/include/sys/syslimits.h)
            const uint32_t pathFileOffset = images[i].pathFileOffset;
            const uint32_t pathFilePage = pathFileOffset / pagesize;
            const off_t pathFilePageOffset = pathFilePage * pagesize;
            const size_t pathFileLen = (pathFileOffset - pathFilePageOffset) + 1024;
            void *pathFile = mmap(NULL, pathFileLen, PROT_READ, MAP_PRIVATE, fd, pathFilePageOffset);
            if (pathFile != MAP_FAILED) {
                const char *path = reinterpret_cast<const char *>(reinterpret_cast<uint8_t *>(pathFile) + pathFileOffset - pathFilePageOffset);
                if (strcmp(filepath, path) == 0) {
                    fprintf(stderr, "Found path is %s\n", path);
                    offset = (images[i].address - dyldBaseAddress);
                    munmap(pathFile, pathFileLen);
                    break;
                } else {
                    munmap(pathFile, pathFileLen);
                }
            } else {
                fprintf(stderr, "ERROR: Failed to mmap image path portion of shared cache file: %s\n", sharedCachePath);
            }
        }

        munmap(data, imagesLen);
    } else {
        fprintf(stderr, "ERROR: Failed to mmap image infos portion of shared cache file: %s\n", sharedCachePath);
    }

    close(fd);

    return offset;
}

NSString *nameForLocalSymbol(NSString *sharedCachePath, uint64_t dylibOffset, uint64_t symbolAddress) {
    NSString *name = nil;

    int fd = open([sharedCachePath UTF8String], O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "Failed to open the shared cache file.\n");
        return nil;
    }

    size_t headerSize = sizeof(dyld_cache_header);
    dyld_cache_header *header = reinterpret_cast<dyld_cache_header *>(malloc(headerSize));
    if (read(fd, header, headerSize) < 0) {
        fprintf(stderr, "Failed to read the shared cache header.\n");
        free(header);
        close(fd);
        return nil;
    }
    // NOTE: Local symbol offset/size fields did not exist in earlier firmware.
    // TODO: At what point were they introduced?
    if (header->mappingOffset < sizeof(dyld_cache_header)) return nil;
    const BOOL is64Bit = (strstr(header->magic, "arm64") != NULL);
    const uint64_t localSymbolsOffset = header->localSymbolsOffset;
    const uint64_t localSymbolsSize = header->localSymbolsSize;
    free(header);

    void *data = mmap(NULL, localSymbolsSize, PROT_READ, MAP_PRIVATE, fd, localSymbolsOffset);
    dyld_cache_local_symbols_info *localSymbols = reinterpret_cast<dyld_cache_local_symbols_info *>(data);
    close(fd);
    if (localSymbols != MAP_FAILED) {
        dyld_cache_local_symbols_entry *entries = reinterpret_cast<dyld_cache_local_symbols_entry *>(reinterpret_cast<uint8_t *>(localSymbols) + localSymbols->entriesOffset);
        for (uint32_t i = 0; i < localSymbols->entriesCount; ++i) {
            dyld_cache_local_symbols_entry *entry = &entries[i];
            if (entry->dylibOffset == dylibOffset) {
                for (uint32_t j = 0; j < entry->nlistCount; ++j) {
                    if (is64Bit) {
                        const struct nlist_64 *nlists = reinterpret_cast<const struct nlist_64 *>((uint64_t)localSymbols + localSymbols->nlistOffset);
                        const struct nlist_64 *n = &nlists[entry->nlistStartIndex + j];
                        if (n->n_value == symbolAddress) {
                            if (n->n_un.n_strx != 0 && (n->n_type & N_STAB) == 0) {
                                const char *strings = reinterpret_cast<const char *>((uint64_t)localSymbols + localSymbols->stringsOffset);
                                name = [NSString stringWithCString:(strings + n->n_un.n_strx) encoding:NSASCIIStringEncoding];
                            }
                            break;
                        }
                    } else {
                        const struct nlist *nlists = reinterpret_cast<const struct nlist *>((uint64_t)localSymbols + localSymbols->nlistOffset);
                        const struct nlist *n = &nlists[entry->nlistStartIndex + j];
                        if (n->n_value == symbolAddress) {
                            if (n->n_un.n_strx != 0 && (n->n_type & N_STAB) == 0) {
                                const char *strings = reinterpret_cast<const char *>((uint64_t)localSymbols + localSymbols->stringsOffset);
                                name = [NSString stringWithCString:(strings + n->n_un.n_strx) encoding:NSASCIIStringEncoding];
                            }
                            break;
                        }
                    }
                }
                break;
            }
        }
        munmap(localSymbols, localSymbolsSize);
    } else {
        fprintf(stderr, "Failed to mmap the shared cache.\n");
    }

    return name;
}

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
