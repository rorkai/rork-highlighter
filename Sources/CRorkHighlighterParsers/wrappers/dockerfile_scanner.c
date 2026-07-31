/// Compiles the upstream Dockerfile scanner with bounded string lengths.
/// Oversized heredocs are rejected by the scanner's existing buffer check.
#include <stddef.h>
#include <string.h>

#include "../languages/dockerfile/tree_sitter/parser.h"

/// Returns a string length capped at Tree-sitter's serialization capacity.
/// The cap keeps the upstream scanner's unsigned arithmetic representable.
static unsigned rork_highlighter_dockerfile_string_length(
    const char *string
) {
    size_t length = strlen(string);
    if (length >= TREE_SITTER_SERIALIZATION_BUFFER_SIZE) {
        return TREE_SITTER_SERIALIZATION_BUFFER_SIZE;
    }
    return (unsigned)length;
}

#define strlen rork_highlighter_dockerfile_string_length
#include "../languages/dockerfile/scanner.c"
#undef strlen
