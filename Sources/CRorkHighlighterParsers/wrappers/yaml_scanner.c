/// Compiles the upstream YAML scanner while isolating one known Clang warning.
/// The narrowed size is bounded by the fixed Tree-sitter serialization buffer.
#if defined(__clang__)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wshorten-64-to-32"
#endif

#include "../languages/yaml/scanner.c"

#if defined(__clang__)
#pragma clang diagnostic pop
#endif
