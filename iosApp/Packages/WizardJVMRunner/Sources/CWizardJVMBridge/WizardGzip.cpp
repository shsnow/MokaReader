// WizardJVMRunner — Apache License 2.0
// Plain zlib gzip helpers for Mihon .tachibk backups.

#include "include/WizardJVMBridge.h"

#include <cstdlib>
#include <cstring>
#include <vector>
#include <zlib.h>

namespace {

constexpr int kGzipWindowBits = 15 + 16; // zlib window + gzip wrapper

}

extern "C" WJBStatus wjb_gzip_decompress(
    const unsigned char *input,
    size_t input_size,
    unsigned char **output,
    size_t *output_size
) {
    if (input == nullptr || output == nullptr || output_size == nullptr) {
        return WJBStatusInvalidArgument;
    }
    *output = nullptr;
    *output_size = 0;

    z_stream stream{};
    if (inflateInit2(&stream, kGzipWindowBits) != Z_OK) {
        return WJBStatusCompressionFailed;
    }

    std::vector<unsigned char> result;
    result.reserve(input_size * 4);
    unsigned char chunk[64 * 1024];
    stream.next_in = const_cast<unsigned char *>(input);
    stream.avail_in = static_cast<uInt>(input_size);

    int status = Z_OK;
    do {
        stream.next_out = chunk;
        stream.avail_out = sizeof(chunk);
        status = inflate(&stream, Z_NO_FLUSH);
        if (status != Z_OK && status != Z_STREAM_END) {
            inflateEnd(&stream);
            return WJBStatusCompressionFailed;
        }
        result.insert(result.end(), chunk, chunk + (sizeof(chunk) - stream.avail_out));
    } while (status != Z_STREAM_END);

    inflateEnd(&stream);

    auto *buffer = static_cast<unsigned char *>(std::malloc(result.size()));
    if (buffer == nullptr) {
        return WJBStatusAllocationFailed;
    }
    std::memcpy(buffer, result.data(), result.size());
    *output = buffer;
    *output_size = result.size();
    return WJBStatusOK;
}

extern "C" WJBStatus wjb_gzip_compress(
    const unsigned char *input,
    size_t input_size,
    unsigned char **output,
    size_t *output_size
) {
    if (input == nullptr || output == nullptr || output_size == nullptr) {
        return WJBStatusInvalidArgument;
    }
    *output = nullptr;
    *output_size = 0;

    z_stream stream{};
    int status = deflateInit2(
        &stream,
        Z_DEFAULT_COMPRESSION,
        Z_DEFLATED,
        kGzipWindowBits,
        8,
        Z_DEFAULT_STRATEGY
    );
    if (status != Z_OK) {
        return WJBStatusCompressionFailed;
    }

    std::vector<unsigned char> result;
    result.reserve(input_size / 2 + 64);
    unsigned char chunk[64 * 1024];
    stream.next_in = const_cast<unsigned char *>(input);
    stream.avail_in = static_cast<uInt>(input_size);

    do {
        stream.next_out = chunk;
        stream.avail_out = sizeof(chunk);
        status = deflate(&stream, Z_FINISH);
        if (status == Z_STREAM_ERROR) {
            deflateEnd(&stream);
            return WJBStatusCompressionFailed;
        }
        result.insert(result.end(), chunk, chunk + (sizeof(chunk) - stream.avail_out));
    } while (status != Z_STREAM_END);

    deflateEnd(&stream);

    auto *buffer = static_cast<unsigned char *>(std::malloc(result.size()));
    if (buffer == nullptr) {
        return WJBStatusAllocationFailed;
    }
    std::memcpy(buffer, result.data(), result.size());
    *output = buffer;
    *output_size = result.size();
    return WJBStatusOK;
}

extern "C" void wjb_buffer_free(unsigned char *value) {
    std::free(value);
}
