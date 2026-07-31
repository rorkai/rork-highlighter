#ifndef C_RORK_HIGHLIGHTER_PARSERS_H
#define C_RORK_HIGHLIGHTER_PARSERS_H

/// Represents an immutable Tree-sitter language definition.
typedef struct TSLanguage TSLanguage;

#ifdef __cplusplus
extern "C" {
#endif

/// Returns the process-lifetime Tree-sitter language for Astro.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_astro(void);

/// Returns the process-lifetime Tree-sitter language for Bash.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_bash(void);

/// Returns the process-lifetime Tree-sitter language for C.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_c(void);

/// Returns the process-lifetime Tree-sitter language for C++.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_cpp(void);

/// Returns the process-lifetime Tree-sitter language for CSS.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_css(void);

/// Returns the process-lifetime Tree-sitter language for Dockerfile.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_dockerfile(void);

/// Returns the process-lifetime Tree-sitter language for dotenv.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_dotenv(void);

/// Returns the process-lifetime Tree-sitter language for Go.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_go(void);

/// Returns the process-lifetime Tree-sitter language for GraphQL.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_graphql(void);

/// Returns the process-lifetime Tree-sitter language for Groovy.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_groovy(void);

/// Returns the process-lifetime Tree-sitter language for HTML.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_html(void);

/// Returns the process-lifetime Tree-sitter language for Java.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_java(void);

/// Returns the process-lifetime Tree-sitter language for JavaScript.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_javascript(void);

/// Returns the process-lifetime Tree-sitter language for JSDoc.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_jsdoc(void);

/// Returns the process-lifetime Tree-sitter language for JSON.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_json(void);

/// Returns the process-lifetime Tree-sitter language for JSON5.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_json5(void);

/// Returns the process-lifetime Tree-sitter language for Kotlin.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_kotlin(void);

/// Returns the process-lifetime Tree-sitter language for Markdown.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_markdown(void);

/// Returns the process-lifetime Tree-sitter language for Markdown Inline.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_markdown_inline(void);

/// Returns the process-lifetime Tree-sitter language for MDX.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_mdx(void);

/// Returns the process-lifetime Tree-sitter language for Objective-C.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_objc(void);

/// Returns the process-lifetime Tree-sitter language for Java Properties.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_properties(void);

/// Returns the process-lifetime Tree-sitter language for Python.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_python(void);

/// Returns the process-lifetime Tree-sitter language for Regular Expression.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_regex(void);

/// Returns the process-lifetime Tree-sitter language for Ruby.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_ruby(void);

/// Returns the process-lifetime Tree-sitter language for Rust.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_rust(void);

/// Returns the process-lifetime Tree-sitter language for SCSS.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_scss(void);

/// Returns the process-lifetime Tree-sitter language for SQL.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_sql(void);

/// Returns the process-lifetime Tree-sitter language for Svelte.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_svelte(void);

/// Returns the process-lifetime Tree-sitter language for Swift.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_swift(void);

/// Returns the process-lifetime Tree-sitter language for TOML.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_toml(void);

/// Returns the process-lifetime Tree-sitter language for TSX.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_tsx(void);

/// Returns the process-lifetime Tree-sitter language for TypeScript.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_typescript(void);

/// Returns the process-lifetime Tree-sitter language for Vue.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_vue(void);

/// Returns the process-lifetime Tree-sitter language for XML.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_xml(void);

/// Returns the process-lifetime Tree-sitter language for YAML.
/// The returned pointer remains valid until the process exits.
const TSLanguage *tree_sitter_yaml(void);

#ifdef __cplusplus
}
#endif

#endif
