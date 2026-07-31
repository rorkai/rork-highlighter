/// Supplies the renderer-neutral themes bundled with Rork Highlighter.
extension HighlightTheme {
    /// Provides a dark theme for code shown on near-black backgrounds.
    public static let rorkDark: Self = {
        let comment = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x7F_8C_98),
            textTraits: [.italic]
        )
        let constant = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0xC7_92_EA)
        )
        let declaration = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x82_AA_FF)
        )
        let error = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0xFF_5C_77),
            textTraits: [.bold]
        )
        let escape = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0xFF_CA_85)
        )
        let function = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0xFF_D5_80)
        )
        let keyword = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0xD9_9B_FF)
        )
        let number = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0xD0_BF_69)
        )
        let punctuation = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x8B_93_A7)
        )
        let string = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0xA8_E6_A3)
        )
        let type = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x5A_D4_E6)
        )

        return Self(
            name: "Rork Dark",
            baseStyle: HighlightStyle(
                foregroundColor: HighlightColor(rgb: 0xD8_DE_E9),
                textTraits: []
            ),
            styles: [
                "at-root": keyword,
                "attribute": declaration,
                "autoreleasepool": keyword,
                "available": keyword,
                "boolean": constant,
                "catch": keyword,
                "character": string,
                "charset": keyword,
                "comment": comment,
                "compatibility_alias": keyword,
                "conditional": keyword,
                "constant": constant,
                "constant.builtin": escape,
                "constructor": declaration,
                "debug": keyword,
                "defs": keyword,
                "delimiter": punctuation,
                "dynamic": keyword,
                "each": keyword,
                "end": keyword,
                "error": error,
                "escape": escape,
                "exception": keyword,
                "extend": keyword,
                "field": declaration,
                "finally": keyword,
                "float": number,
                "for": keyword,
                "forward": keyword,
                "function": function,
                "implementation": keyword,
                "import": keyword,
                "include": keyword,
                "interface": type,
                "keyframes": keyword,
                "keyword": keyword,
                "label": constant,
                "markup.heading": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x82_AA_FF),
                    textTraits: [.bold]
                ),
                "markup.italic": HighlightStyle(
                    textTraits: [.italic]
                ),
                "markup.link": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x89_DD_FF),
                    textTraits: [.underline]
                ),
                "markup.raw": string,
                "markup.strikethrough": HighlightStyle(
                    textTraits: [.strikethrough]
                ),
                "markup.strong": HighlightStyle(
                    textTraits: [.bold]
                ),
                "markup.underline": HighlightStyle(
                    textTraits: [.underline]
                ),
                "media": keyword,
                "method": function,
                "mixin": keyword,
                "namespace": constant,
                "number": number,
                "operator": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x89_DD_FF)
                ),
                "optional": keyword,
                "parameter": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0xF0_C6_74)
                ),
                "preproc": keyword,
                "property": declaration,
                "protocol": type,
                "punctuation": punctuation,
                "repeat": keyword,
                "required": keyword,
                "return": keyword,
                "selector": declaration,
                "storageclass": keyword,
                "string": string,
                "string.escape": escape,
                "string.special": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0xF2_B5_D4)
                ),
                "supports": keyword,
                "synchronized": keyword,
                "synthesize": keyword,
                "tag": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0xFF_7A_90)
                ),
                "tag.attribute": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0xC3_E8_8D)
                ),
                "tag.delimiter": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x89_DD_FF)
                ),
                "text.emphasis": HighlightStyle(
                    textTraits: [.italic]
                ),
                "text.literal": string,
                "text.reference": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x89_DD_FF),
                    textTraits: [.underline]
                ),
                "text.strong": HighlightStyle(
                    textTraits: [.bold]
                ),
                "text.title": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x82_AA_FF),
                    textTraits: [.bold]
                ),
                "text.uri": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x89_DD_FF),
                    textTraits: [.underline]
                ),
                "throw": keyword,
                "try": keyword,
                "type": type,
                "use": keyword,
                "variable.builtin": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0xFF_8F_70)
                ),
                "variable.member": declaration,
                "variable.parameter": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0xF0_C6_74)
                ),
                "warn": error,
                "while": keyword,
            ]
        )
    }()

    /// Provides a light theme for code shown on white backgrounds.
    public static let rorkLight: Self = {
        let comment = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x6E_77_81),
            textTraits: [.italic]
        )
        let constant = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x82_50_DF)
        )
        let declaration = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x05_50_AE)
        )
        let error = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0xCF_22_2E),
            textTraits: [.bold]
        )
        let escape = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x9A_67_00)
        )
        let function = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x66_39_BA)
        )
        let keyword = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0xA4_0E_4C)
        )
        let number = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x95_38_00)
        )
        let punctuation = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x57_60_6A)
        )
        let string = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x11_63_29)
        )
        let type = HighlightStyle(
            foregroundColor: HighlightColor(rgb: 0x05_50_AE)
        )

        return Self(
            name: "Rork Light",
            baseStyle: HighlightStyle(
                foregroundColor: HighlightColor(rgb: 0x24_29_2F),
                textTraits: []
            ),
            styles: [
                "at-root": keyword,
                "attribute": declaration,
                "autoreleasepool": keyword,
                "available": keyword,
                "boolean": constant,
                "catch": keyword,
                "character": string,
                "charset": keyword,
                "comment": comment,
                "compatibility_alias": keyword,
                "conditional": keyword,
                "constant": constant,
                "constant.builtin": escape,
                "constructor": declaration,
                "debug": keyword,
                "defs": keyword,
                "delimiter": punctuation,
                "dynamic": keyword,
                "each": keyword,
                "end": keyword,
                "error": error,
                "escape": escape,
                "exception": keyword,
                "extend": keyword,
                "field": declaration,
                "finally": keyword,
                "float": number,
                "for": keyword,
                "forward": keyword,
                "function": function,
                "implementation": keyword,
                "import": keyword,
                "include": keyword,
                "interface": type,
                "keyframes": keyword,
                "keyword": keyword,
                "label": constant,
                "markup.heading": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x05_50_AE),
                    textTraits: [.bold]
                ),
                "markup.italic": HighlightStyle(
                    textTraits: [.italic]
                ),
                "markup.link": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x09_69_DA),
                    textTraits: [.underline]
                ),
                "markup.raw": string,
                "markup.strikethrough": HighlightStyle(
                    textTraits: [.strikethrough]
                ),
                "markup.strong": HighlightStyle(
                    textTraits: [.bold]
                ),
                "markup.underline": HighlightStyle(
                    textTraits: [.underline]
                ),
                "media": keyword,
                "method": function,
                "mixin": keyword,
                "namespace": constant,
                "number": number,
                "operator": declaration,
                "optional": keyword,
                "parameter": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x95_38_00)
                ),
                "preproc": keyword,
                "property": declaration,
                "protocol": type,
                "punctuation": punctuation,
                "repeat": keyword,
                "required": keyword,
                "return": keyword,
                "selector": declaration,
                "storageclass": keyword,
                "string": string,
                "string.escape": escape,
                "string.special": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x82_50_DF)
                ),
                "supports": keyword,
                "synchronized": keyword,
                "synthesize": keyword,
                "tag": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0xCF_22_2E)
                ),
                "tag.attribute": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x95_38_00)
                ),
                "tag.delimiter": punctuation,
                "text.emphasis": HighlightStyle(
                    textTraits: [.italic]
                ),
                "text.literal": string,
                "text.reference": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x09_69_DA),
                    textTraits: [.underline]
                ),
                "text.strong": HighlightStyle(
                    textTraits: [.bold]
                ),
                "text.title": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x05_50_AE),
                    textTraits: [.bold]
                ),
                "text.uri": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x09_69_DA),
                    textTraits: [.underline]
                ),
                "throw": keyword,
                "try": keyword,
                "type": type,
                "use": keyword,
                "variable.builtin": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x95_38_00)
                ),
                "variable.member": declaration,
                "variable.parameter": HighlightStyle(
                    foregroundColor: HighlightColor(rgb: 0x95_38_00)
                ),
                "warn": error,
                "while": keyword,
            ]
        )
    }()
}
