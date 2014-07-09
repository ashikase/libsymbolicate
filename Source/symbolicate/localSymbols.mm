/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for parsing and symbolicating iOS crash log files.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: GPL v3 (See LICENSE file for details)
 */

#include "localSymbols.h"

#include <fcntl.h>
#include <mach-o/nlist.h>
#include <sys/mman.h>
#include <sys/stat.h>

#import "Headers.h"

typedef struct _dyld_cache_header {
    char     magic[16];
    uint32_t mappingOffset;
    uint32_t mappingCount;
    uint32_t imagesOffset;
    uint32_t imagesCount;
    uint64_t dyldBaseAddress;
    uint64_t codeSignatureOffset;
    uint64_t codeSignatureSize;
    uint64_t slideInfoOffset;
    uint64_t slideInfoSize;
    uint64_t localSymbolsOffset;
    uint64_t localSymbolsSize;
    //uint8_t  uuid[16];
} dyld_cache_header;

typedef struct _dyld_cache_local_symbols_info {
    uint32_t nlistOffset;
    uint32_t nlistCount;
    uint32_t stringsOffset;
    uint32_t stringsSize;
    uint32_t entriesOffset;
    uint32_t entriesCount;
} dyld_cache_local_symbols_info;

typedef struct _dyld_cache_local_symbols_entry {
    uint32_t dylibOffset;
    uint32_t nlistStartIndex;
    uint32_t nlistCount;
} dyld_cache_local_symbols_entry;

NSString *nameForLocalSymbol(NSString *sharedCachePath, uint64_t dylibOffset, uint64_t symbolAddress) {
    NSString *name = nil;

    int fd = open([sharedCachePath UTF8String], O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "Failed to open the shared cache file.\n");
        return nil;
    }

    struct stat st;
    if (fstat(fd, &st) < 0) {
        fprintf(stderr, "Failed to fstat() the shared cache file.\n");
        return nil;
    }

    size_t headerSize = sizeof(dyld_cache_header);
    dyld_cache_header *header = reinterpret_cast<dyld_cache_header *>(malloc(headerSize));
    if (read(fd, header, headerSize) < 0) {
        fprintf(stderr, "Failed to read the shared cache header.\n");
        free(header);
        return nil;
    }
    // NOTE: Local symbol offset/size fields did not exist in earlier firmware.
    // TODO: At what point were they introduced?
    if (header->mappingOffset < sizeof(_dyld_cache_header)) return nil;
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
