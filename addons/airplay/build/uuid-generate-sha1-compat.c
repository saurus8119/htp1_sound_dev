
/*
 * Compatibility implementation for uuid_generate_sha1, missing from
 * Debian Stretch's older libuuid.
 * Implements RFC 4122 name-based UUID version 5 using SHA-1.
 */
#include <stddef.h>
#include <string.h>
#include <uuid/uuid.h>
#include <openssl/sha.h>

void uuid_generate_sha1(uuid_t out, const uuid_t ns,
                        const char *name, size_t len) {
    unsigned char digest[SHA_DIGEST_LENGTH];
    SHA_CTX ctx;

    SHA1_Init(&ctx);
    SHA1_Update(&ctx, ns, 16);
    SHA1_Update(&ctx, name, len);
    SHA1_Final(digest, &ctx);

    memcpy(out, digest, 16);
    out[6] = (unsigned char)((out[6] & 0x0fU) | 0x50U);
    out[8] = (unsigned char)((out[8] & 0x3fU) | 0x80U);
}
