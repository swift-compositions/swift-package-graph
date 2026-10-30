import Testing

@testable import Package_Graph

@Suite
struct `Package.Trait.Mismatch` {}

extension `Package.Trait.Mismatch` {

    /// A package with one library product `Library` built from target `Library`, plus a test
    /// target, that depends on `dependencies`.
    private func package(
        _ name: Swift.String,
        traits: [Package.Manifest.Trait] = [],
        dependencies: [(Swift.String, [Package.Dependency.Evaluation.Trait])] = [],
        uses: [Package::Target.Dependency] = [],
        conditions: [Package::Target.Dependency: Package.Manifest.Condition] = [:],
        testUses: [Package::Target.Dependency] = []
    ) -> Package.Manifest.Evaluation {
        Package.Manifest.Evaluation(
            name: Package.Name(_unchecked: name),
            toolsVersion: Version.Tools(major: 6, minor: 1),
            dependencies: dependencies.map { identity, traits in
                Package.Dependency.Evaluation(
                    source: .fileSystem(identity: .init(identity), path: "/fixture/\(identity)"),
                    traits: traits
                )
            },
            products: [
                .init(name: "Library", kind: .library(.automatic), targets: ["Library"])
            ],
            targets: [
                .init(name: "Library", kind: .regular, dependencies: uses, conditions: conditions),
                .init(name: "Tests", kind: .test, dependencies: testUses + [.target(name: "Library")]),
            ],
            traits: traits
        )
    }

    private func use(_ package: Swift.String) -> Package::Target.Dependency {
        .product(name: "Library", package: Package.Name(_unchecked: package))
    }

    @Test
    func `a trait requested on a dependency no product uses is a mismatch`() {
        let mismatches = Package.Trait.Mismatch.all(in: [
            package("kernel", dependencies: [("serializer", [.init(name: "Always")])])
        ])

        #expect(mismatches.map(\.kind) == [.unused])
        #expect(mismatches.map(\.traits) == [[.init(name: "Always")]])
        #expect(mismatches.map(\.consequences) == [nil])
    }

    @Test
    func `a dependency used only by a test target counts as unused`() {
        let mismatches = Package.Trait.Mismatch.all(in: [
            package(
                "kernel",
                dependencies: [("serializer", [.init(name: "Always")])],
                testUses: [use("serializer")]
            )
        ])

        #expect(mismatches.map(\.kind) == [.unused])
    }

    @Test
    func `a request for defaults on an unused dependency is a mismatch`() {
        let mismatches = Package.Trait.Mismatch.all(in: [
            package("kernel", dependencies: [("serializer", [.init(name: "default")])])
        ])

        #expect(mismatches.map(\.kind) == [.unused])
    }

    @Test
    func `a request on a dependency used unconditionally is not a mismatch`() {
        let mismatches = Package.Trait.Mismatch.all(in: [
            package(
                "kernel",
                dependencies: [("serializer", [.init(name: "Always")])],
                uses: [use("serializer")]
            )
        ])

        #expect(mismatches.isEmpty)
    }

    @Test
    func `disabling a dependency's traits requests nothing`() {
        let mismatches = Package.Trait.Mismatch.all(in: [
            package("kernel", dependencies: [("serializer", [])])
        ])

        #expect(mismatches.isEmpty)
    }

    @Test
    func `an unconditional request on a dependency used only under a trait is a mismatch`() {
        let mismatches = Package.Trait.Mismatch.all(in: [
            package(
                "argument",
                traits: [.init(name: "Text")],
                dependencies: [("text", [.init(name: "Byte")])],
                uses: [use("text")],
                conditions: [use("text"): .init(traits: ["Text"])]
            )
        ])

        #expect(mismatches.map(\.kind) == [.guarded(by: ["Text"])])
    }

    @Test
    func `a request conditioned on the trait that guards the use is not a mismatch`() {
        let mismatches = Package.Trait.Mismatch.all(in: [
            package(
                "argument",
                traits: [.init(name: "Text")],
                dependencies: [("text", [.init(name: "Byte", condition: .init(traits: ["Text"]))])],
                uses: [use("text")],
                conditions: [use("text"): .init(traits: ["Text"])]
            )
        ])

        #expect(mismatches.isEmpty)
    }

    @Test
    func `a request conditioned on a trait that enables the guarding trait is not a mismatch`() {
        let mismatches = Package.Trait.Mismatch.all(in: [
            package(
                "argument",
                traits: [.init(name: "All", enabledTraits: ["Text"]), .init(name: "Text")],
                dependencies: [("text", [.init(name: "Byte", condition: .init(traits: ["All"]))])],
                uses: [use("text")],
                conditions: [use("text"): .init(traits: ["Text"])]
            )
        ])

        #expect(mismatches.isEmpty)
    }

    @Test
    func `a request conditioned on an unrelated trait is a mismatch`() {
        let mismatches = Package.Trait.Mismatch.all(in: [
            package(
                "argument",
                traits: [.init(name: "Other"), .init(name: "Text")],
                dependencies: [("text", [.init(name: "Byte", condition: .init(traits: ["Other"]))])],
                uses: [use("text")],
                conditions: [use("text"): .init(traits: ["Text"])]
            )
        ])

        #expect(mismatches.map(\.kind) == [.guarded(by: ["Text"])])
    }

    @Test
    func `a platform-only condition is an unconditional use`() {
        let mismatches = Package.Trait.Mismatch.all(in: [
            package(
                "kernel",
                dependencies: [("serializer", [.init(name: "Always")])],
                uses: [use("serializer")],
                conditions: [use("serializer"): .init(platforms: ["linux"])]
            )
        ])

        #expect(mismatches.isEmpty)
    }

    @Test
    func `consequences are the dependencies only the requested traits require`() {
        let serializer = package(
            "serializer",
            traits: [
                .init(name: "default", enabledTraits: ["Pair"]),
                .init(name: "Always"),
                .init(name: "Pair"),
            ],
            dependencies: [("always", []), ("pair", [])],
            uses: [use("always"), use("pair")],
            conditions: [
                use("always"): .init(traits: ["Always"]),
                use("pair"): .init(traits: ["Pair"]),
            ]
        )
        let mismatches = Package.Trait.Mismatch.all(in: [
            package("kernel", dependencies: [("serializer", [.init(name: "Always"), .init(name: "Pair")])]),
            serializer,
        ])

        #expect(mismatches.map(\.consequences) == [["always"]])
    }

    @Test
    func `a requested trait that guards nothing has no consequences`() {
        let mismatches = Package.Trait.Mismatch.all(in: [
            package("kernel", dependencies: [("serializer", [.init(name: "Always")])]),
            package("serializer", traits: [.init(name: "Always")]),
        ])

        #expect(mismatches.map(\.consequences) == [[]])
    }
}
