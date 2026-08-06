import Foundation
import SwiftTreeSitter
import Testing

@testable import RorkHighlighter

/// Verifies every parser and query distributed in the common language pack.
@Suite
struct BundledLanguageTests {
    /// Confirms the fixture corpus covers every bundled language exactly once.
    ///
    /// - Throws: ``HighlighterError`` when the catalog cannot be initialized.
    @Test
    func providesFixtureForEveryBundledLanguage() throws {
        let catalog = try LanguageCatalog.standard()
        let fixtureLanguages = bundledLanguageFixtures.map(\.language)
        let catalogLanguages = catalog.languages.map(\.id)

        #expect(Set(fixtureLanguages).count == fixtureLanguages.count)
        #expect(Set(fixtureLanguages) == Set(catalogLanguages))
    }

    /// Confirms each bundled parser accepts its complete representative source.
    ///
    /// - Parameter fixture: The language and source text to parse.
    /// - Throws: An error when the catalog or parser cannot be initialized.
    @Test(arguments: bundledLanguageFixtures)
    private func parsesBundledLanguage(
        _ fixture: BundledLanguageFixture
    ) throws {
        let catalog = try LanguageCatalog.standard()
        let language = try #require(
            catalog.language(for: fixture.language)
        )
        let parser = Parser()
        try parser.setLanguage(language.configuration.language)

        let tree = try #require(parser.parse(fixture.source))
        let rootNode = try #require(tree.rootNode)
        let parsedNodeTypes = nodeTypes(in: rootNode)

        #expect(
            rootNode.nodeType == fixture.expectedRootNodeType,
            """
            The parser produced an unexpected root node.
            \(rootNode.sExpressionString ?? "No syntax tree was available.")
            """
        )
        #expect(
            !rootNode.hasError,
            """
            The parser produced an error node.
            \(rootNode.sExpressionString ?? "No syntax tree was available.")
            """
        )
        #expect(!rootNode.isMissing)
        #expect(
            rootNode.byteRange
                == 0..<UInt32(fixture.source.utf16.count * 2)
        )
        for expectedNodeType in fixture.expectedNodeTypes {
            #expect(
                parsedNodeTypes.contains(expectedNodeType),
                """
                The parser did not produce the expected \(expectedNodeType) node.
                \(rootNode.sExpressionString ?? "No syntax tree was available.")
                """
            )
        }
    }

    /// Confirms each bundled parser produces a representative highlight scope.
    ///
    /// - Parameter fixture: The language, source text, and expected scope.
    /// - Throws: ``HighlighterError`` when the fixture cannot be highlighted.
    @Test(arguments: bundledLanguageFixtures)
    private func highlightsBundledLanguage(
        _ fixture: BundledLanguageFixture
    ) throws {
        let highlighter = try Highlighter()
        let snapshot = try highlighter.highlight(
            fixture.source,
            as: fixture.language
        )

        #expect(snapshot.language == fixture.language)
        #expect(snapshot.highlights.contains { $0.scope == fixture.expectedScope })
    }

    /// Confirms the optimized one-shot pipeline matches the complete layered
    /// pipeline for every bundled language.
    ///
    /// - Parameter fixture: The language and source text to highlight.
    /// - Throws: ``HighlighterError`` when either pipeline cannot highlight the
    ///   fixture.
    @Test(arguments: bundledLanguageFixtures)
    private func matchesLayeredHighlighting(
        _ fixture: BundledLanguageFixture
    ) throws {
        let highlighter = try Highlighter()
        let definition = try highlighter.languageDefinition(
            for: fixture.language
        )
        let layer = try highlighter.makeLanguageLayer(for: definition)
        layer.replaceContent(with: fixture.source)

        let optimized = try highlighter.highlight(
            fixture.source,
            as: fixture.language
        )
        let layered = try highlighter.makeSnapshot(
            text: fixture.source,
            language: fixture.language,
            revision: 0,
            layer: layer,
            documentLength: fixture.source.utf16.count
        )

        #expect(optimized == layered)
    }

    /// Confirms HTML script elements are highlighted with the JavaScript parser.
    @Test
    func highlightsJavaScriptInjectedIntoHTML() throws {
        let highlighter = try Highlighter()
        let snapshot = try highlighter.highlight(
            "<script>const enabled = true;</script>",
            as: .html
        )

        #expect(snapshot.highlights.contains { $0.scope == "keyword" })
        #expect(snapshot.highlights.contains { $0.scope == "constant.builtin" })
    }

    /// Confirms fenced Markdown code resolves aliases through the same catalog.
    @Test
    func highlightsSwiftInjectedIntoMarkdown() throws {
        let highlighter = try Highlighter()
        let snapshot = try highlighter.highlight(
            """
            # Example

            ```swift
            let enabled = true
            ```
            """,
            as: .markdown
        )

        #expect(snapshot.highlights.contains { $0.scope == "keyword" })
        #expect(snapshot.highlights.contains { $0.scope == "boolean" })
    }

    /// Confirms JavaScript comments and regular expressions use their support
    /// parsers.
    @Test
    func highlightsSupportLanguagesInjectedIntoJavaScript() throws {
        let highlighter = try Highlighter()
        let source = """
            /** @param {string} value */
            const matcher = /(foo|bar)+/;
            """
        let quantifierRange = (source as NSString).range(of: "+")
        let snapshot = try highlighter.highlight(source, as: .javascript)

        #expect(snapshot.highlights.contains { $0.scope == "type" })
        #expect(
            snapshot.highlights.contains {
                $0.scope == "operator"
                    && $0.range
                        == UTF16Range(
                            location: quantifierRange.location,
                            length: quantifierRange.length
                        )
            }
        )
    }

    /// Confirms GraphQL tagged templates resolve the `gql` catalog alias.
    @Test
    func highlightsGraphQLInjectedIntoJavaScript() throws {
        let highlighter = try Highlighter()
        let snapshot = try highlighter.highlight(
            "const schema = gql`type Query { viewer: User }`;",
            as: .javascript
        )

        #expect(snapshot.highlights.contains { $0.scope == "type" })
    }

    /// Confirms Vue script blocks select TypeScript through their language
    /// attribute.
    @Test
    func highlightsTypeScriptInjectedIntoVue() throws {
        let highlighter = try Highlighter()
        let snapshot = try highlighter.highlight(
            #"<script lang="ts">const value: boolean = true;</script>"#,
            as: .vue
        )

        #expect(snapshot.highlights.contains { $0.scope == "type.builtin" })
    }

    /// Collects every concrete node type below a syntax tree root.
    ///
    /// - Parameter rootNode: The root whose descendants should be visited.
    /// - Returns: The unique named and anonymous node types in the tree.
    private func nodeTypes(in rootNode: Node) -> Set<String> {
        var result: Set<String> = []
        var pendingNodes = [rootNode]

        while let node = pendingNodes.popLast() {
            if let nodeType = node.nodeType {
                result.insert(nodeType)
            }
            for childIndex in 0..<node.childCount {
                if let child = node.child(at: childIndex) {
                    pendingNodes.append(child)
                }
            }
        }

        return result
    }
}

/// Holds one representative bundled-language highlighting expectation.
private struct BundledLanguageFixture: CustomTestStringConvertible, Sendable {
    /// Identifies the parser used for the fixture.
    let language: LanguageID

    /// Holds the complete source text parsed by the fixture.
    let source: String

    /// Holds a capture scope that the matching query must produce.
    let expectedScope: String

    /// Holds the grammar root expected for the complete source.
    let expectedRootNodeType: String

    /// Holds representative syntax nodes expected below the root.
    let expectedNodeTypes: Set<String>

    /// Describes the fixture by language in parameterized test output.
    var testDescription: String {
        language.rawValue
    }

    /// Creates one representative highlighting fixture.
    ///
    /// - Parameters:
    ///   - language: The parser used for the fixture.
    ///   - source: The complete source text to parse.
    ///   - expectedScope: The capture scope expected in the result.
    ///   - expectedRootNodeType: The grammar root expected for the source.
    ///   - expectedNodeTypes: The representative syntax nodes expected in the tree.
    init(
        language: LanguageID,
        source: String,
        expectedScope: String,
        expectedRootNodeType: String,
        expectedNodeTypes: Set<String>
    ) {
        self.language = language
        self.source = source
        self.expectedScope = expectedScope
        self.expectedRootNodeType = expectedRootNodeType
        self.expectedNodeTypes = expectedNodeTypes
    }
}

/// Provides one representative source sample for every bundled parser.
private let bundledLanguageFixtures: [BundledLanguageFixture] = [
    BundledLanguageFixture(
        language: .astro,
        source: """
            ---
            const title = "Hello";
            ---
            <main class="app">
              <h1>{title}</h1>
            </main>
            """ + "\n",
        expectedScope: "tag",
        expectedRootNodeType: "document",
        expectedNodeTypes: ["frontmatter", "element", "html_interpolation"]
    ),
    BundledLanguageFixture(
        language: .bash,
        source: """
            #!/usr/bin/env bash
            set -euo pipefail
            name="${1:-Rork}"
            if [[ -n "$name" ]]; then
              echo "Hello, $name"
            fi
            """ + "\n",
        expectedScope: "string",
        expectedRootNodeType: "program",
        expectedNodeTypes: ["variable_assignment", "if_statement", "string"]
    ),
    BundledLanguageFixture(
        language: .c,
        source: """
            #include <stdbool.h>

            typedef struct {
                int value;
            } Widget;

            static bool is_ready(const Widget *widget) {
                return widget != 0 && widget->value > 0;
            }
            """ + "\n",
        expectedScope: "number",
        expectedRootNodeType: "translation_unit",
        expectedNodeTypes: ["preproc_include", "struct_specifier", "function_definition"]
    ),
    BundledLanguageFixture(
        language: .cpp,
        source: """
            #include <string>

            class Widget {
            public:
                explicit Widget(std::string name) : name_(name) {}
                const std::string& name() const { return name_; }

            private:
                std::string name_;
            };
            """ + "\n",
        expectedScope: "keyword",
        expectedRootNodeType: "translation_unit",
        expectedNodeTypes: ["preproc_include", "class_specifier", "function_definition"]
    ),
    BundledLanguageFixture(
        language: .css,
        source: """
            :root {
              --accent: #7c3aed;
            }

            body .card:hover {
              color: var(--accent);
              display: grid;
            }

            @media (min-width: 768px) {
              .card { grid-template-columns: 1fr 1fr; }
            }
            """ + "\n",
        expectedScope: "tag",
        expectedRootNodeType: "stylesheet",
        expectedNodeTypes: ["rule_set", "declaration", "media_statement"]
    ),
    BundledLanguageFixture(
        language: .dockerfile,
        source: """
            FROM node:22-alpine AS build
            WORKDIR /app
            COPY package*.json ./
            RUN npm ci
            COPY . .
            CMD ["npm", "start"]
            """ + "\n",
        expectedScope: "keyword",
        expectedRootNodeType: "source_file",
        expectedNodeTypes: ["from_instruction", "run_instruction", "json_string_array"]
    ),
    BundledLanguageFixture(
        language: .dotenv,
        source: """
            EXPO_PUBLIC_API_URL=https://api.example.com
            ENABLED=true
            EMPTY=
            """ + "\n",
        expectedScope: "constant",
        expectedRootNodeType: "document",
        expectedNodeTypes: ["assignment", "identifier", "boolean"]
    ),
    BundledLanguageFixture(
        language: .go,
        source: """
            package main

            import "fmt"

            type App struct {
                Name string
            }

            func (app App) Greet() string {
                return fmt.Sprintf("Hello, %s", app.Name)
            }

            var version = 1
            """ + "\n",
        expectedScope: "number",
        expectedRootNodeType: "source_file",
        expectedNodeTypes: ["import_declaration", "type_declaration", "method_declaration"]
    ),
    BundledLanguageFixture(
        language: .graphql,
        source: """
            query Viewer($id: ID!) {
              user(id: $id) {
                ...UserFields
              }
            }

            fragment UserFields on User {
              id
              name
            }
            """ + "\n",
        expectedScope: "keyword",
        expectedRootNodeType: "source_file",
        expectedNodeTypes: ["operation_definition", "fragment_definition", "variable_definition"]
    ),
    BundledLanguageFixture(
        language: .groovy,
        source: """
            class Greeter {
                String greet(String name) {
                    def enabled = true
                    return "Hello, ${name}"
                }
            }
            """ + "\n",
        expectedScope: "boolean",
        expectedRootNodeType: "source_file",
        expectedNodeTypes: ["class_definition", "function_definition", "interpolation"]
    ),
    BundledLanguageFixture(
        language: .html,
        source: """
            <!doctype html>
            <html lang="en">
              <head><title>Rork</title></head>
              <body>
                <main data-ready="true">Hello</main>
              </body>
            </html>
            """ + "\n",
        expectedScope: "tag",
        expectedRootNodeType: "document",
        expectedNodeTypes: ["doctype", "element", "attribute"]
    ),
    BundledLanguageFixture(
        language: .java,
        source: """
            package com.example;

            public final class Greeter {
                private final String name;

                public Greeter(String name) {
                    this.name = name;
                }

                public String greeting() {
                    return "Hello, " + name;
                }
            }
            """ + "\n",
        expectedScope: "keyword",
        expectedRootNodeType: "program",
        expectedNodeTypes: ["package_declaration", "class_declaration", "method_declaration"]
    ),
    BundledLanguageFixture(
        language: .javascript,
        source: """
            export async function fetchUser(id) {
              const response = await fetch(`/users/${id}`);
              return response.json();
            }
            """ + "\n",
        expectedScope: "keyword",
        expectedRootNodeType: "program",
        expectedNodeTypes: ["export_statement", "function_declaration", "await_expression"]
    ),
    BundledLanguageFixture(
        language: .jsdoc,
        source: """
            /**
             * Greets a user.
             * @param {string} name The display name.
             * @returns {Promise<string>} A greeting.
             */
            """ + "\n",
        expectedScope: "keyword",
        expectedRootNodeType: "document",
        expectedNodeTypes: ["description", "tag", "type"]
    ),
    BundledLanguageFixture(
        language: .json,
        source: """
            {
              "name": "Rork",
              "enabled": true,
              "targets": ["ios", "web"],
              "settings": {
                "retries": 3
              }
            }
            """ + "\n",
        expectedScope: "string.special.key",
        expectedRootNodeType: "document",
        expectedNodeTypes: ["object", "array", "pair"]
    ),
    BundledLanguageFixture(
        language: .json5,
        source: """
            {
              // Expo accepts JSON5-style configuration.
              name: 'Rork',
              enabled: true,
              targets: ['ios', 'web'],
            }
            """ + "\n",
        expectedScope: "constant.builtin.boolean",
        expectedRootNodeType: "file",
        expectedNodeTypes: ["object", "array", "comment"]
    ),
    BundledLanguageFixture(
        language: .kotlin,
        source: """
            package com.example

            data class User(val name: String)

            fun User.greeting(): String = "Hello, $name"

            val enabled = true
            """ + "\n",
        expectedScope: "keyword",
        expectedRootNodeType: "source_file",
        expectedNodeTypes: ["package_header", "class_declaration", "function_declaration"]
    ),
    BundledLanguageFixture(
        language: .markdown,
        source: """
            # Rork

            Modern mobile development includes:

            - Swift
            - Kotlin
            - TypeScript

            Read the [documentation](https://example.com).

            ```swift
            let enabled = true
            ```
            """ + "\n",
        expectedScope: "text.title",
        expectedRootNodeType: "document",
        expectedNodeTypes: ["atx_heading", "list", "fenced_code_block"]
    ),
    BundledLanguageFixture(
        language: .markdownInline,
        source: "**bold**, *emphasized*, [linked](https://example.com), and `code`.",
        expectedScope: "text.strong",
        expectedRootNodeType: "inline",
        expectedNodeTypes: ["strong_emphasis", "emphasis", "inline_link", "code_span"]
    ),
    BundledLanguageFixture(
        language: .mdx,
        source: """
            export const title = "Rork"

            # Rork

            <Card enabled>
              Welcome, **developer**.
            </Card>
            """ + "\n",
        expectedScope: "text.title",
        expectedRootNodeType: "document",
        expectedNodeTypes: ["export_statement", "atx_heading", "jsx_element"]
    ),
    BundledLanguageFixture(
        language: .objectiveC,
        source: """
            #import <Foundation/Foundation.h>

            @interface Greeter : NSObject
            @property(nonatomic, copy) NSString *name;
            - (instancetype)initWithName:(NSString *)name;
            @end

            @implementation Greeter
            - (instancetype)initWithName:(NSString *)name {
                self = [super init];
                if (self) {
                    _name = [name copy];
                }
                return self;
            }
            @end
            """ + "\n",
        expectedScope: "keyword",
        expectedRootNodeType: "translation_unit",
        expectedNodeTypes: ["class_interface", "class_implementation", "method_definition"]
    ),
    BundledLanguageFixture(
        language: .properties,
        source: """
            # Application settings
            app.name=Rork
            enabled=true
            greeting=Hello\\ World
            """ + "\n",
        expectedScope: "property",
        expectedRootNodeType: "file",
        expectedNodeTypes: ["comment", "property", "key"]
    ),
    BundledLanguageFixture(
        language: .python,
        source: """
            from dataclasses import dataclass

            @dataclass
            class User:
                name: str

                def greeting(self) -> str:
                    return f"Hello, {self.name}"
            """ + "\n",
        expectedScope: "keyword",
        expectedRootNodeType: "module",
        expectedNodeTypes: ["import_from_statement", "class_definition", "function_definition"]
    ),
    BundledLanguageFixture(
        language: .regex,
        source: #"^(http|https):\/\/([a-z0-9.-]+)(\/.*)?$"#,
        expectedScope: "punctuation.bracket",
        expectedRootNodeType: "pattern",
        expectedNodeTypes: ["anonymous_capturing_group", "alternation", "one_or_more"]
    ),
    BundledLanguageFixture(
        language: .ruby,
        source: """
            class User
              attr_reader :name

              def initialize(name:)
                @name = name
              end

              def greeting
                "Hello, #{@name}"
              end
            end
            """ + "\n",
        expectedScope: "keyword",
        expectedRootNodeType: "program",
        expectedNodeTypes: ["class", "method", "string"]
    ),
    BundledLanguageFixture(
        language: .rust,
        source: """
            #[derive(Debug)]
            struct User {
                name: String,
            }

            impl User {
                fn greeting(&self) -> String {
                    format!("Hello, {}", self.name)
                }
            }
            """ + "\n",
        expectedScope: "keyword",
        expectedRootNodeType: "source_file",
        expectedNodeTypes: ["struct_item", "impl_item", "function_item"]
    ),
    BundledLanguageFixture(
        language: .scss,
        source: """
            $accent: #7c3aed;

            @mixin card($padding: 1rem) {
              padding: $padding;
            }

            .card {
              @include card(1rem);

              &:hover {
                color: $accent;
              }
            }
            """ + "\n",
        expectedScope: "variable",
        expectedRootNodeType: "stylesheet",
        expectedNodeTypes: ["mixin_statement", "include_statement", "rule_set"]
    ),
    BundledLanguageFixture(
        language: .sql,
        source: """
            CREATE TABLE users (
              id INTEGER PRIMARY KEY,
              name TEXT NOT NULL,
              enabled BOOLEAN DEFAULT TRUE
            );

            SELECT id, name
            FROM users
            WHERE enabled = TRUE
            ORDER BY name;
            """ + "\n",
        expectedScope: "keyword",
        expectedRootNodeType: "program",
        expectedNodeTypes: ["create_table", "select", "where"]
    ),
    BundledLanguageFixture(
        language: .svelte,
        source: """
            <script lang="ts">
              export let name: string;
              let count = 0;
            </script>

            <button on:click={() => count += 1}>{name}: {count}</button>

            <style>
              button { color: rebeccapurple; }
            </style>
            """ + "\n",
        expectedScope: "tag",
        expectedRootNodeType: "document",
        expectedNodeTypes: ["script_element", "element", "style_element"]
    ),
    BundledLanguageFixture(
        language: .swift,
        source: """
            import Foundation

            struct User: Sendable {
                let name: String

                func greeting() -> String {
                    "Hello, \\(name)"
                }
            }

            let users = [User(name: "Rork")]
            """ + "\n",
        expectedScope: "keyword",
        expectedRootNodeType: "source_file",
        expectedNodeTypes: ["import_declaration", "class_declaration", "function_declaration"]
    ),
    BundledLanguageFixture(
        language: .toml,
        source: """
            [app]
            name = "Rork"
            enabled = true
            targets = ["ios", "web"]

            [app.theme]
            accent = "#7c3aed"
            """ + "\n",
        expectedScope: "boolean",
        expectedRootNodeType: "document",
        expectedNodeTypes: ["table", "pair", "array"]
    ),
    BundledLanguageFixture(
        language: .tsx,
        source: """
            interface GreetingProps {
              name: string;
              enabled?: boolean;
            }

            export function Greeting({ name, enabled = true }: GreetingProps) {
              return <h1 data-enabled={enabled}>Hello, {name}</h1>;
            }
            """ + "\n",
        expectedScope: "tag",
        expectedRootNodeType: "program",
        expectedNodeTypes: ["interface_declaration", "function_declaration", "jsx_element"]
    ),
    BundledLanguageFixture(
        language: .typescript,
        source: """
            interface User {
              id: string;
              enabled: boolean;
            }

            export async function loadUser(id: string): Promise<User> {
              const response = await fetch(`/users/${id}`);
              return response.json() as Promise<User>;
            }
            """ + "\n",
        expectedScope: "type.builtin",
        expectedRootNodeType: "program",
        expectedNodeTypes: ["interface_declaration", "function_declaration", "type_annotation"]
    ),
    BundledLanguageFixture(
        language: .vue,
        source: """
            <script setup lang="ts">
            const props = defineProps<{ name: string }>()
            </script>

            <template>
              <h1 v-if="props.name">Hello, {{ props.name }}</h1>
            </template>

            <style scoped>
            h1 { color: rebeccapurple; }
            </style>
            """ + "\n",
        expectedScope: "tag",
        expectedRootNodeType: "document",
        expectedNodeTypes: ["script_element", "template_element", "style_element"]
    ),
    BundledLanguageFixture(
        language: .xml,
        source: """
            <?xml version="1.0" encoding="UTF-8"?>
            <manifest xmlns="https://example.com/schema">
              <application enabled="true">
                <name>Rork</name>
              </application>
            </manifest>
            """ + "\n",
        expectedScope: "tag",
        expectedRootNodeType: "document",
        expectedNodeTypes: ["XMLDecl", "element", "Attribute"]
    ),
    BundledLanguageFixture(
        language: .yaml,
        source: """
            name: Rork
            targets:
              - ios
              - web
            defaults: &defaults
              enabled: true
            production:
              <<: *defaults
              api_url: https://api.example.com
            """ + "\n",
        expectedScope: "boolean",
        expectedRootNodeType: "stream",
        expectedNodeTypes: ["block_mapping", "block_sequence", "anchor"]
    ),
]
