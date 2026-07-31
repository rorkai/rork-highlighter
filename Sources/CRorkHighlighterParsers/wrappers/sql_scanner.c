/// Compiles the upstream SQL scanner with a representable string length.
/// Oversized dollar-quote tags fail the scanner's existing buffer check.
#include <limits.h>
#include <stddef.h>
#include <string.h>

/// Returns a string length that remains representable after adding one.
/// The upstream scanner compares the result with its serialization capacity.
static int rork_highlighter_sql_string_length(const char *string) {
    size_t length = strlen(string);
    if (length >= (size_t)INT_MAX) {
        return INT_MAX - 1;
    }
    return (int)length;
}

#define strlen rork_highlighter_sql_string_length
#include "../languages/sql/scanner.c"
#undef strlen
