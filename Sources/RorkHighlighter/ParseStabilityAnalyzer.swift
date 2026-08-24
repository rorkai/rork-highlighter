import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer

/// Locates the leading source whose parse no longer depends on unseen input.
///
/// Streamed documents usually end in the middle of a token or construct.
/// Tree-sitter recovers by inserting zero-width tokens and grouping
/// unexpected input into `ERROR` nodes, and it can reinterpret that recovered
/// syntax as soon as the next chunk arrives. The analyzer walks the parsed
/// layer trees and returns the UTF-16 length of the prefix that sits before
/// every end-connected recovery artifact and before the still-growing final
/// token. Captures inside that prefix match what a one-shot highlight of the
/// same text produces and rarely change when more source is appended.
enum ParseStabilityAnalyzer {
    /// Returns the stable UTF-16 prefix length for parsed language layers.
    ///
    /// - Parameters:
    ///   - rootNodes: The root syntax node of every parsed language layer.
    ///   - text: The source represented by the parsed layers.
    ///   - documentLength: The UTF-16 length of the parsed source.
    /// - Returns: The length of the prefix unaffected by end-of-input
    ///   recovery and token growth.
    static func stableUTF16Length(
        of rootNodes: [Node],
        text: String,
        documentLength: Int
    ) -> Int {
        guard documentLength > 0 else {
            return 0
        }

        let codeUnits = Array(text.utf16)
        var trailingTokenStart = documentLength
        var latestLeaf: NSRange?
        var regions: [NSRange] = []
        var pendingFields: [(position: Int, influence: NSRange)] = []

        for rootNode in rootNodes {
            collectRecoveryRegions(under: rootNode, into: &regions)

            guard
                let leafRange = trailingVisibleLeafRange(
                    under: rootNode,
                    collectingZeroWidthNodesInto: &pendingFields
                )
            else {
                continue
            }
            if let currentLeaf = latestLeaf,
                currentLeaf.location >= leafRange.location
            {
                continue
            }
            latestLeaf = leafRange
        }

        // A zero-width node marks a field still waiting for input only when
        // it sits where input arrives. Grammars also emit zero-width
        // structural markers in front of existing content, and those carry
        // no pending classification.
        for pendingField in pendingFields
        where
            isWhitespace(
                codeUnits,
                from: pendingField.position,
                to: documentLength
            )
        {
            regions.append(pendingField.influence)
        }

        // A document that ends exactly at its final token can extend that
        // token with the next appended chunk, so the token's classification
        // is not settled. Trailing whitespace separates the final token from
        // future input and removes the hazard. Layers refine each other, so
        // the token that starts last across every layer decides the
        // boundary. That token belongs to the innermost injected language at
        // the document tail.
        if let latestLeaf, latestLeaf.upperBound >= documentLength {
            trailingTokenStart = latestLeaf.location
        }

        let stableLength = min(
            trailingTokenStart,
            recoverySuffixStart(
                connecting: regions,
                text: text,
                documentLength: documentLength
            )
        )
        return min(max(stableLength, 0), documentLength)
    }

    /// Returns the trailing token range and gathers tail recovery nodes.
    ///
    /// The walk follows the last visible child at every level. Zero-width
    /// children skipped along the way can be fields still waiting for input
    /// even when the grammar produced them without an error flag, so they
    /// are reported with their construct-level influence for filtering by
    /// document position.
    ///
    /// - Parameters:
    ///   - rootNode: The root syntax node of one language layer.
    ///   - pendingFields: The candidate pending fields and their influence.
    /// - Returns: The UTF-16 range of the trailing visible token, or `nil`
    ///   when the layer parsed no visible tokens.
    private static func trailingVisibleLeafRange(
        under rootNode: Node,
        collectingZeroWidthNodesInto pendingFields:
            inout [(position: Int, influence: NSRange)]
    ) -> NSRange? {
        var node = rootNode
        guard node.range.length > 0 else {
            return nil
        }

        while node.childCount > 0 {
            var visibleChild: Node?
            for childIndex in stride(
                from: node.childCount - 1,
                through: 0,
                by: -1
            ) {
                guard let child = node.child(at: childIndex) else {
                    continue
                }
                guard child.range.length == 0 else {
                    visibleChild = child
                    break
                }
                pendingFields.append(
                    (
                        position: child.range.location,
                        influence: influenceRange(
                            ofZeroWidth: child,
                            below: rootNode
                        )
                    )
                )
            }

            guard let visibleChild else {
                return node.range
            }
            node = visibleChild
        }

        return node.range
    }

    /// Returns the offset where end-connected parser recovery begins.
    ///
    /// Regions that reach the document end mark unsettled syntax, regions
    /// touching an unsettled region merge into it, and whitespace between a
    /// region and unsettled syntax does not separate them because it carries
    /// no tokens of its own. Artifacts followed by settled source stay
    /// disconnected because appended input starts after that settled source
    /// and cannot reshape them any more than a finished document could.
    ///
    /// - Parameters:
    ///   - regions: The influence regions of every recovery artifact.
    ///   - text: The source represented by the parsed layers.
    ///   - documentLength: The UTF-16 length of the parsed source.
    /// - Returns: The start of the connected recovery suffix, or the document
    ///   length when recovery does not reach the end.
    private static func recoverySuffixStart(
        connecting regions: [NSRange],
        text: String,
        documentLength: Int
    ) -> Int {
        guard !regions.isEmpty else {
            return documentLength
        }

        let codeUnits = Array(text.utf16)
        var suffixStart = documentLength
        var didConnectRegion = true
        while didConnectRegion {
            didConnectRegion = false
            for region in regions
            where
                region.location < suffixStart
                && isWhitespace(
                    codeUnits,
                    from: region.upperBound,
                    to: suffixStart
                )
            {
                suffixStart = region.location
                didConnectRegion = true
            }
        }

        return suffixStart
    }

    /// Returns whether a UTF-16 window contains only whitespace.
    ///
    /// An empty or inverted window is vacuously whitespace, which lets
    /// overlapping recovery regions connect without a separate overlap test.
    ///
    /// - Parameters:
    ///   - codeUnits: The complete source as UTF-16 code units.
    ///   - start: The first offset of the window.
    ///   - end: The first offset after the window.
    /// - Returns: `true` when no code unit in the window is a token
    ///   character.
    private static func isWhitespace(
        _ codeUnits: [UInt16],
        from start: Int,
        to end: Int
    ) -> Bool {
        let lower = max(0, start)
        let upper = min(codeUnits.count, end)
        guard lower < upper else {
            return true
        }

        for offset in lower..<upper {
            switch codeUnits[offset] {
            case 0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x0020, 0x0085,
                0x00A0, 0x2028, 0x2029:
                continue
            default:
                return false
            }
        }
        return true
    }

    /// Collects the influence region of every recovery artifact in a layer.
    ///
    /// The walk descends only into subtrees whose `hasError` flag is set, so
    /// healthy documents finish immediately. An `ERROR` node influences its
    /// own extent because it spans exactly the input the parser reinterpreted
    /// as unexpected. Zero-width nodes influence their position or their
    /// construct depending on whether they stand for a required field.
    ///
    /// - Parameters:
    ///   - rootNode: The root syntax node of one language layer.
    ///   - regions: The collected influence regions in UTF-16 units.
    private static func collectRecoveryRegions(
        under rootNode: Node,
        into regions: inout [NSRange]
    ) {
        guard rootNode.hasError else {
            return
        }

        var pendingNodes = [rootNode]
        while let node = pendingNodes.popLast() {
            if node.isMissing || node.range.length == 0 {
                regions.append(
                    influenceRange(ofZeroWidth: node, below: rootNode)
                )
                continue
            }
            if node.nodeType == Self.errorNodeType {
                regions.append(node.range)
                continue
            }

            for childIndex in 0..<node.childCount {
                guard
                    let child = node.child(at: childIndex),
                    child.hasError
                else {
                    continue
                }
                pendingNodes.append(child)
            }
        }
    }

    /// Returns the influence of one zero-width recovery node.
    ///
    /// A zero-width anonymous token is an invented closer, such as a brace
    /// or quote. The parser inserts it while it still recognizes the
    /// construct, so the construct's parsed children keep the
    /// classifications a finished document would give them and only the
    /// token's own position stays speculative. A zero-width named node
    /// stands for a required field, and query patterns classify the field's
    /// siblings differently once real input fills it. Its influence covers
    /// the nearest ancestor that already has visible named children, which
    /// is the construct whose classification depends on the absent field.
    ///
    /// - Parameters:
    ///   - node: The zero-width recovery node.
    ///   - rootNode: The root syntax node of the containing layer.
    /// - Returns: The UTF-16 range whose classifications stay speculative.
    private static func influenceRange(
        ofZeroWidth node: Node,
        below rootNode: Node
    ) -> NSRange {
        guard node.isNamed else {
            return node.range
        }

        var ancestor = node.parent
        while let candidate = ancestor, candidate != rootNode {
            if candidate.isNamed, hasVisibleNamedChild(candidate) {
                return candidate.range
            }
            ancestor = candidate.parent
        }
        return node.range
    }

    /// Returns whether a node has at least one named child with source text.
    ///
    /// - Parameter node: The node whose children are inspected.
    /// - Returns: `true` when a named child covers at least one code unit.
    private static func hasVisibleNamedChild(_ node: Node) -> Bool {
        for childIndex in 0..<node.childCount {
            guard
                let child = node.child(at: childIndex),
                child.isNamed,
                child.range.length > 0
            else {
                continue
            }
            return true
        }
        return false
    }

    /// Names the node type Tree-sitter assigns to unexpected input.
    private static let errorNodeType = "ERROR"
}

/// Adds conveniences for the layered tree snapshots produced by sessions.
extension ParseStabilityAnalyzer {
    /// Returns the stable UTF-16 prefix length for a layered tree snapshot.
    ///
    /// - Parameters:
    ///   - treeSnapshot: The root layer snapshot and its injected sublayers.
    ///   - text: The source represented by the parsed layers.
    ///   - documentLength: The UTF-16 length of the parsed source.
    /// - Returns: The length of the prefix unaffected by end-of-input
    ///   recovery and token growth.
    static func stableUTF16Length(
        of treeSnapshot: LanguageLayerTreeSnapshot,
        text: String,
        documentLength: Int
    ) -> Int {
        var rootNodes: [Node] = []
        collectRootNodes(of: treeSnapshot, into: &rootNodes)
        return stableUTF16Length(
            of: rootNodes,
            text: text,
            documentLength: documentLength
        )
    }

    /// Collects the root syntax node of every layer in a tree snapshot.
    ///
    /// - Parameters:
    ///   - treeSnapshot: The layer snapshot whose trees are collected.
    ///   - rootNodes: The root nodes gathered across nested layers.
    private static func collectRootNodes(
        of treeSnapshot: LanguageLayerTreeSnapshot,
        into rootNodes: inout [Node]
    ) {
        if let rootNode = treeSnapshot.rootSnapshot.tree.rootNode {
            rootNodes.append(rootNode)
        }
        for sublayerSnapshot in treeSnapshot.sublayerSnapshots {
            collectRootNodes(of: sublayerSnapshot, into: &rootNodes)
        }
    }
}
