/// Compiles the upstream Python scanner while isolating known Clang warnings.
/// Every narrowed value is bounded by the fixed Tree-sitter serialization buffer.
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshorten-64-to-32"
#endif

#include "../languages/python/scanner.c"

#if defined(__clang__)
#pragma clang diagnostic pop
#endif
