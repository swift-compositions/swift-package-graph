public import Package_Graph
internal import SwiftParser
internal import SwiftSyntax
internal import SwiftSyntaxBuilder

extension Package.Manifest.Rewrite {

    /// `source` with the plan applied, and what was done to it.
    public func apply(to source: Swift.String) -> Outcome {
        let rewriter = Rewriter(self)
        let rewritten = rewriter.rewrite(Parser.parse(source: source))
        let census = Census(organizations: self.organizations)
        census.walk(rewritten)
        return Outcome(
            source: rewritten.description,
            versioned: rewriter.versioned,
            removed: rewriter.removed,
            conditioned: rewriter.conditioned,
            unreached: census.unreached
        )
    }
}

extension Package.Manifest.Rewrite {

    /// A `.package(...)` call in a manifest, read from its `url:` or `path:` argument.
    fileprivate struct Declaration {
        let call: FunctionCallExprSyntax

        /// The lowercased last path component, without `.git`: SwiftPM's identity of the package.
        let identity: Swift.String

        /// The GitHub organization of a `url:` dependency; `nil` for any other location.
        let organization: Swift.String?

        init?(_ expression: ExprSyntax) {
            guard let call = expression.as(FunctionCallExprSyntax.self),
                let member = call.calledExpression.as(MemberAccessExprSyntax.self),
                member.declName.baseName.text == "package"
            else { return nil }
            guard
                let location = call.arguments.first(where: {
                    ["url", "path"].contains($0.label?.text)
                }),
                let literal = location.expression.as(StringLiteralExprSyntax.self),
                let text = literal.representedLiteralValue
            else { return nil }
            var components = text.split(separator: "/").map(Swift.String.init)
            guard var last = components.popLast() else { return nil }
            if last.hasSuffix(".git") { last.removeLast(4) }
            self.call = call
            self.identity = last.lowercased()
            if location.label?.text == "url", let host = components.firstIndex(of: "github.com"),
                components.indices.contains(host + 1)
            {
                self.organization = components[host + 1]
            } else {
                self.organization = nil
            }
        }
    }

    fileprivate final class Rewriter: SyntaxRewriter {
        let plan: Package.Manifest.Rewrite
        var versioned = 0
        var removed: [Swift.String] = []
        var conditioned: [Swift.String] = []

        init(_ plan: Package.Manifest.Rewrite) {
            self.plan = plan
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: ArrayElementListSyntax) -> ArrayElementListSyntax {
            var kept: [ArrayElementSyntax] = []
            for element in node {
                if let declaration = Declaration(element.expression),
                    self.plan.removals.contains(declaration.identity)
                {
                    self.removed.append(declaration.identity)
                    continue
                }
                kept.append(element)
            }
            if let last = kept.last, node.last?.trailingComma != nil, last.trailingComma == nil {
                kept[kept.count - 1] = last.with(\.trailingComma, .commaToken())
            }
            return super.visit(ArrayElementListSyntax(kept))
        }

        override func visit(_ node: FunctionCallExprSyntax) -> ExprSyntax {
            guard let declaration = Declaration(ExprSyntax(node)) else {
                return super.visit(node)
            }
            var call = node
            if let version = self.plan.version, let organization = declaration.organization,
                self.plan.organizations.contains(organization),
                let index = call.arguments.firstIndex(where: { argument in
                    argument.label?.text == "branch"
                        && argument.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue == "main"
                })
            {
                let branch = call.arguments[index]
                call.arguments[index] = LabeledExprSyntax(
                    leadingTrivia: branch.leadingTrivia,
                    expression: ExprSyntax(".upToNextMinor(from: \(literal: version))"),
                    trailingComma: branch.trailingComma
                )
                self.versioned += 1
            }
            if let traits = self.plan.conditions[declaration.identity],
                let index = call.arguments.firstIndex(where: { $0.label?.text == "traits" }),
                let array = call.arguments[index].expression.as(ArrayExprSyntax.self)
            {
                var elements = array.elements
                for position in elements.indices {
                    let element = elements[position]
                    guard let name = Self.name(of: element.expression), let guards = traits[name]
                    else { continue }
                    let condition = guards.sorted().map { "\"\($0)\"" }.joined(separator: ", ")
                    elements[position] = element.with(
                        \.expression,
                        ExprSyntax(".trait(name: \(literal: name), condition: .when(traits: [\(raw: condition)]))")
                            .with(\.leadingTrivia, element.expression.leadingTrivia)
                            .with(\.trailingTrivia, element.expression.trailingTrivia)
                    )
                    self.conditioned.append("\(declaration.identity).\(name)")
                }
                call.arguments[index].expression = ExprSyntax(array.with(\.elements, elements))
            }
            return ExprSyntax(call)
        }

        /// The trait a request names: `"T"` or `.trait(name: "T", ...)`.
        static func name(of expression: ExprSyntax) -> Swift.String? {
            if let literal = expression.as(StringLiteralExprSyntax.self) {
                return literal.representedLiteralValue
            }
            guard let call = expression.as(FunctionCallExprSyntax.self),
                call.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text == "trait",
                let name = call.arguments.first(where: { $0.label?.text == "name" })
            else { return nil }
            return name.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        }
    }

    /// Finds dependencies on `organizations` that are still branch- or revision-based.
    fileprivate final class Census: SyntaxVisitor {
        let organizations: Swift.Set<Swift.String>
        var unreached: [Swift.String] = []

        init(organizations: Swift.Set<Swift.String>) {
            self.organizations = organizations
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            if let declaration = Declaration(ExprSyntax(node)),
                let organization = declaration.organization,
                self.organizations.contains(organization),
                node.arguments.contains(where: { ["branch", "revision"].contains($0.label?.text) })
            {
                self.unreached.append(declaration.identity)
            }
            return .visitChildren
        }
    }
}
