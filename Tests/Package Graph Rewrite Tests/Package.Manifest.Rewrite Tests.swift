import SwiftParser
import SwiftSyntax
import Testing

@testable import Package_Graph_Rewrite

@Suite
struct `Package.Manifest.Rewrite` {}

extension `Package.Manifest.Rewrite` {

    private func rewrite(
        _ source: Swift.String,
        removals: Swift.Set<Swift.String> = [],
        conditions: [Swift.String: [Swift.String: Swift.Set<Swift.String>]] = [:]
    ) -> Package.Manifest.Rewrite.Outcome {
        Package.Manifest.Rewrite(
            version: "0.0.100",
            organizations: ["swift-atoms", "swift-molecules"],
            removals: removals,
            conditions: conditions
        ).apply(to: source)
    }

    private func parses(_ source: Swift.String) -> Swift.Bool {
        !Parser.parse(source: source).hasError
    }

    @Test
    func `a branch dependency on a versioned organization gets the version`() {
        let outcome = rewrite(
            """
            let package = Package(name: "p", dependencies: [
                .package(url: "https://github.com/swift-atoms/swift-point.git", branch: "main", traits: ["Affine"]),
            ])
            """
        )

        #expect(
            outcome.source == """
                let package = Package(name: "p", dependencies: [
                    .package(url: "https://github.com/swift-atoms/swift-point.git", .upToNextMinor(from: "0.0.100"), traits: ["Affine"]),
                ])
                """
        )
        #expect(outcome.versioned == 1)
        #expect(outcome.unreached.isEmpty)
        #expect(parses(outcome.source))
    }

    @Test
    func `a multi-line branch dependency keeps its layout`() {
        let outcome = rewrite(
            """
            let package = Package(name: "p", dependencies: [
                .package(
                    url: "https://github.com/swift-atoms/swift-terminal.git",
                    branch: "main",
                    traits: ["Error"]
                ),
            ])
            """
        )

        #expect(outcome.source.contains("        .upToNextMinor(from: \"0.0.100\"),\n"))
        #expect(outcome.versioned == 1)
        #expect(parses(outcome.source))
    }

    @Test
    func `dependencies on other organizations are left alone`() {
        let source = """
            let package = Package(name: "p", dependencies: [
                .package(url: "https://github.com/swiftlang/swift-syntax.git", "604.0.0"..<"605.0.0"),
                .package(url: "https://github.com/pointfreeco/swift-x.git", branch: "main"),
            ])
            """
        let outcome = rewrite(source)

        #expect(outcome.source == source)
        #expect(outcome.versioned == 0)
        #expect(outcome.unreached.isEmpty)
    }

    @Test
    func `a removed dependency leaves a valid array, single- and multi-line`() {
        let outcome = rewrite(
            """
            let package = Package(name: "p", dependencies: [
                .package(url: "https://github.com/swift-atoms/swift-ascii.git", branch: "main", traits: ["Parser"]),
                .package(url: "https://github.com/swift-atoms/swift-point.git", branch: "main"),
                .package(
                    url: "https://github.com/swift-molecules/swift-storage.git",
                    branch: "main",
                    traits: [.trait(name: "Memory", condition: .when(traits: ["A"]))]
                )
            ])
            """,
            removals: ["swift-ascii", "swift-storage"]
        )

        #expect(!outcome.source.contains("swift-ascii"))
        #expect(!outcome.source.contains("swift-storage"))
        #expect(outcome.source.contains("swift-point"))
        #expect(Swift.Set(outcome.removed) == ["swift-ascii", "swift-storage"])
        #expect(parses(outcome.source))
    }

    @Test
    func `removing every dependency leaves an empty array`() {
        let outcome = rewrite(
            """
            let package = Package(name: "p", dependencies: [
                .package(url: "https://github.com/swift-atoms/swift-ascii.git", branch: "main"),
            ])
            """,
            removals: ["swift-ascii"]
        )

        #expect(outcome.removed == ["swift-ascii"])
        #expect(parses(outcome.source))
    }

    @Test
    func `guarded trait requests get the guarding condition, in both spellings`() {
        let outcome = rewrite(
            """
            let package = Package(name: "p", dependencies: [
                .package(url: "https://github.com/swift-atoms/swift-text.git", branch: "main", traits: ["Byte", "Other", .trait(name: "Index", condition: .when(traits: ["X"]))]),
            ])
            """,
            conditions: ["swift-text": ["Byte": ["Text"], "Index": ["Text", "All"]]]
        )

        #expect(outcome.source.contains(#".trait(name: "Byte", condition: .when(traits: ["Text"]))"#))
        #expect(outcome.source.contains(#".trait(name: "Index", condition: .when(traits: ["All", "Text"]))"#))
        #expect(outcome.source.contains(#""Other""#))
        #expect(Swift.Set(outcome.conditioned) == ["swift-text.Byte", "swift-text.Index"])
        #expect(parses(outcome.source))
    }

    @Test
    func `a requirement built outside the call is reported as unreached`() {
        let outcome = rewrite(
            """
            let package = Package(name: "p", dependencies: [
                .package(url: "https://github.com/swift-atoms/swift-point.git", branch: "main"),
                .package(url: "https://github.com/swift-atoms/swift-cpu.git", revision: "abc"),
            ])
            """
        )

        #expect(outcome.versioned == 1)
        #expect(outcome.unreached == ["swift-cpu"])
    }
}

extension `Package.Manifest.Rewrite` {

    private func evaluation(
        dependencies: [Swift.String: [Package.Dependency.Evaluation.Trait]],
        targets: [Package.Manifest.Target]
    ) -> Package.Manifest.Evaluation {
        Package.Manifest.Evaluation(
            name: "p",
            toolsVersion: Version.Tools(major: 6, minor: 1),
            dependencies: dependencies.keys.sorted().map { identity in
                Package.Dependency.Evaluation(
                    source: .fileSystem(identity: .init(identity), path: "/fixture/\(identity)"),
                    traits: dependencies[identity] ?? []
                )
            },
            products: [.init(name: "P", kind: .library(.automatic), targets: ["P"])],
            targets: targets
        )
    }

    @Test
    func `the plan removes unreferenced unused dependencies and retains test-only ones`() {
        let evaluation = evaluation(
            dependencies: [
                "swift-ascii": [.init(name: "Parser")],
                "swift-point": [.init(name: "Affine")],
                "swift-text": [.init(name: "Byte"), .init(name: "default")],
            ],
            targets: [
                .init(
                    name: "P",
                    kind: .regular,
                    dependencies: [.product(name: "Text", package: "swift-text")],
                    conditions: [.product(name: "Text", package: "swift-text"): .init(traits: ["Text"])]
                ),
                .init(name: "Tests", kind: .test, dependencies: [.product(name: "Point", package: "swift-point")]),
            ]
        )
        let plan = Package.Manifest.Rewrite(
            evaluation: evaluation,
            mismatches: Package.Trait.Mismatch.all(in: [evaluation]),
            version: "0.0.100",
            organizations: ["swift-atoms"]
        )

        #expect(plan.removals == ["swift-ascii"])
        #expect(plan.retained == ["swift-point"])
        #expect(plan.conditions == ["swift-text": ["Byte": ["Text"]]])
    }
}

extension `Package.Manifest.Rewrite` {

    @Test
    func `the organizations parse from the array institute organizations prints`() {
        let roster = #"["swift-institute","swift-atoms","swift-molecules","swift-standards","swift-arm-ltd","swift-bipm","swift-ecma","swift-iec","swift-ieee","swift-ietf","swift-incits","swift-intel","swift-iso","swift-linux-foundation","swift-microsoft","swift-riscv","swift-w3c","swift-whatwg","swift-compositions"]"#

        let organizations = Package.Manifest.Rewrite.organizations(parsing: roster + "\n")

        #expect(organizations?.count == 19)
        #expect(organizations?.contains("swift-bipm") == true)
        #expect(Package.Manifest.Rewrite.organizations(parsing: #"[ "swift-atoms" , "swift-iso" ]"#) == ["swift-atoms", "swift-iso"])
    }

    @Test(arguments: [
        "", "[]", "[ ]", "swift-atoms", #""swift-atoms""#, #"["swift-atoms",]"#, #"["", "swift-atoms"]"#,
        #"["Swift-Atoms"]"#, #"[swift-atoms]"#, #"["swift atoms"]"#, #"{"organizations": ["swift-atoms"]}"#,
    ])
    func `anything but a non-empty array of organization names is refused`(input: Swift.String) {
        #expect(Package.Manifest.Rewrite.organizations(parsing: input) == nil)
    }
}

