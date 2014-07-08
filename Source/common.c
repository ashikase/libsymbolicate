static unsigned char nibble(char c) {
    if (c >= '0' && c <= '9') {
        return c - '0';
    } else if (c >= 'a' && c <= 'f') {
        return c - 'a' + 10;
    } else if (c >= 'A' && c <= 'F') {
        return c - 'A' + 10;
    } else {
        return 0xFF;
    }
}

unsigned long long unsignedLongLongFromHexString(const char* str, int len) {
    unsigned long long res = 0;
    int i;
    for (i = 0; i < len; ++ i) {
        unsigned char n = nibble(str[i]);
        if (n != 0xFF) {
            res = res * 16 + n;
        }
    }
    return res;
}

/* vim: set ft=c ff=unix sw=4 ts=4 tw=80 expandtab: */
