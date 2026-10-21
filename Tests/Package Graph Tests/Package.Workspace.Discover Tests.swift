import Environment
import File_System
import Paths
import Testing

@testable import Package_Graph

@Suite
struct `Package.Workspace.discover` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
}

extension `Package.Workspace.discover`.Integration {

    @Test
    func `minimal workspace yields one manifest`() async throws {
        let root = try makeTempDirectory()
        defer { deleteTempDirectory(root) }

        try writePackage(
            atDirectory: root / "swift-leaf",
            name: "swift-leaf",
            dependencies: []
        )

        let workspace = try await Package.Workspace.discover(at: root)
        #expect(workspace.manifests.count == 1)
        #expect(workspace.manifests[0].name == "swift-leaf")
        #expect(workspace.manifests[0].dependencies.isEmpty)
    }

    @Test
    func `chain workspace yields three manifests with correct adjacency`() async throws {
        let root = try makeTempDirectory()
        defer { deleteTempDirectory(root) }

        try writePackage(
            atDirectory: root / "swift-c",
            name: "swift-c",
            dependencies: []
        )
        try writePackage(
            atDirectory: root / "swift-b",
            name: "swift-b",
            dependencies: [(localName: "swift-c", relativePath: "../swift-c")]
        )
        try writePackage(
            atDirectory: root / "swift-a",
            name: "swift-a",
            dependencies: [(localName: "swift-b", relativePath: "../swift-b")]
        )

        let workspace = try await Package.Workspace.discover(at: root)
        #expect(workspace.manifests.count == 3)

        let byName = Swift.Dictionary(
            uniqueKeysWithValues: workspace.manifests.map { ($0.name, $0) }
        )
        #expect(byName["swift-a"]?.dependencies.count == 1)
        #expect(byName["swift-b"]?.dependencies.count == 1)
        #expect(byName["swift-c"]?.dependencies.isEmpty == true)

        let graph = try Package.Graph(workspace)
        let order = try graph.topologicalOrder()
        let cIndex = order.firstIndex(of: "swift-c") ?? .max
        let bIndex = order.firstIndex(of: "swift-b") ?? .max
        let aIndex = order.firstIndex(of: "swift-a") ?? .max
        #expect(cIndex < bIndex)
        #expect(bIndex < aIndex)
    }

    @Test
    func `diamond workspace yields four manifests, no cycles`() async throws {
        let root = try makeTempDirectory()
        defer { deleteTempDirectory(root) }

        try writePackage(
            atDirectory: root / "swift-d",
            name: "swift-d",
            dependencies: []
        )
        try writePackage(
            atDirectory: root / "swift-b",
            name: "swift-b",
            dependencies: [(localName: "swift-d", relativePath: "../swift-d")]
        )
        try writePackage(
            atDirectory: root / "swift-c",
            name: "swift-c",
            dependencies: [(localName: "swift-d", relativePath: "../swift-d")]
        )
        try writePackage(
            atDirectory: root / "swift-a",
            name: "swift-a",
            dependencies: [
                (localName: "swift-b", relativePath: "../swift-b"),
                (localName: "swift-c", relativePath: "../swift-c"),
            ]
        )

        let workspace = try await Package.Workspace.discover(at: root)
        #expect(workspace.manifests.count == 4)

        let graph = try Package.Graph(workspace)
        #expect(graph.cycles().isEmpty)
    }

    @Test
    func `nonexistent root throws .rootDoesNotExist`() async throws {
        let root = try Paths.Path(
            "/tmp/this-path-does-not-exist-\(Swift.Int.random(in: 0...Swift.Int.max))"
        )
        do throws(Package.Workspace.Error) {
            _ = try await Package.Workspace.discover(at: root)
            Issue.record("expected throw")
        } catch {
            #expect(error.kind == .rootDoesNotExist)
        }
    }

    @Test
    func `empty workspace throws .noPackagesFound`() async throws {
        let root = try makeTempDirectory()
        defer { deleteTempDirectory(root) }

        do throws(Package.Workspace.Error) {
            _ = try await Package.Workspace.discover(at: root)
            Issue.record("expected throw")
        } catch {
            #expect(error.kind == .noPackagesFound)
        }
    }
}

private func makeTempDirectory() throws -> Paths.Path {
    let suffix = Swift.String(Swift.Int.random(in: 0...Swift.Int.max), radix: 36)
    let environment = Environment.Snapshot.current()
    let base = try Paths.Path(environment["TMPDIR"] ?? environment["TEMP"] ?? "/tmp")
    let path = base / Paths.Path.Component(stringLiteral: "package-graph-tests-\(suffix)")
    let dir = File.Directory(path)
    try dir.create.recursive()
    return path
}

private func deleteTempDirectory(_ path: Paths.Path) {
    let dir = File.Directory(path)
    try? dir.delete.recursive()
}

private func writePackage(
    atDirectory directory: Paths.Path,
    name: Swift.String,
    dependencies: [(localName: Swift.String, relativePath: Swift.String)]
) throws {
    let dir = File.Directory(directory)
    try dir.create.recursive()

    let sourcesDir = directory / "Sources" / Paths.Path.Component(stringLiteral: name)
    let sourcesDirHandle = File.Directory(sourcesDir)
    try sourcesDirHandle.create.recursive()

    let placeholderFile = File(sourcesDir / "Placeholder.swift")
    try placeholderFile.write.atomic("// auto-generated test fixture\n")

    let depEntries = dependencies.map { dep in
        ".package(path: \"\(dep.relativePath)\")"
    }.joined(separator: ",\n        ")

    let depTargets = dependencies.map { dep in
        ".product(name: \"\(dep.localName)\", package: \"\(dep.localName)\")"
    }.joined(separator: ",\n                ")

    let depsBlock =
        depEntries.isEmpty
        ? ""
        : "    dependencies: [\n        \(depEntries)\n    ],\n"
    let depTargetsBlock =
        depTargets.isEmpty
        ? ""
        : "            dependencies: [\n                \(depTargets)\n            ],\n"

    let manifest = """
        // swift-tools-version: 6.4
        import PackageDescription

        let package = Package(
            name: "\(name)",
        \(depsBlock)    targets: [
                .target(
                    name: "\(name)",
        \(depTargetsBlock)            path: "Sources/\(name)"
                )
            ]
        )
        """
    let manifestFile = File(directory / "Package.swift")
    try manifestFile.write.atomic(manifest)
}
