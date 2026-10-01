import Testing

@testable import Package_Graph

@Suite
struct `Package.Graph` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
}

extension `Package.Graph`.Unit {
    @Test
    func `Empty workspace produces empty graph`() throws {
        let workspace = Package.Workspace(root: "/tmp", manifests: [])
        let graph = try Package.Graph(workspace)
        #expect(graph.packages.isEmpty)
        #expect(graph.directDependents(of: "anything").isEmpty)
        #expect(graph.directDependencies(of: "anything").isEmpty)
    }

    @Test
    func `Single package, no deps`() throws {
        let manifest = Package.Manifest(
            name: "swift-leaf",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: []
        )
        let workspace = Package.Workspace(root: "/tmp", manifests: [manifest])
        let graph = try Package.Graph(workspace)

        #expect(graph.packages == ["swift-leaf"])
        #expect(graph.directDependents(of: "swift-leaf").isEmpty)
        #expect(graph.directDependencies(of: "swift-leaf").isEmpty)
        #expect(graph.manifest(for: "swift-leaf") != nil)
    }

    @Test
    func `Linear chain A→B→C: reverse-dep queries`() throws {
        let a = Package.Manifest(
            name: "swift-a",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [
                Package.Dependency(
                    source: .path("../swift-b"),
                    name: "swift-b",
                    products: ["B"]
                )
            ]
        )
        let b = Package.Manifest(
            name: "swift-b",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [
                Package.Dependency(
                    source: .path("../swift-c"),
                    name: "swift-c",
                    products: ["C"]
                )
            ]
        )
        let c = Package.Manifest(name: "swift-c", toolsVersion: Version.Tools(major: 6, minor: 3))

        let workspace = Package.Workspace(root: "/tmp", manifests: [a, b, c])
        let graph = try Package.Graph(workspace)

        #expect(graph.directDependents(of: "swift-c") == ["swift-b"])
        #expect(graph.directDependents(of: "swift-b") == ["swift-a"])
        #expect(graph.directDependents(of: "swift-a").isEmpty)

        let waves = graph.transitiveDependents(of: "swift-c", depth: .max)
        #expect(waves.count == 2)
        #expect(waves[0].depth == 1)
        #expect(waves[0].packages == ["swift-b"])
        #expect(waves[1].depth == 2)
        #expect(waves[1].packages == ["swift-a"])
    }

    @Test
    func `Diamond A→B, A→C, B→D, C→D: D's dependents collapse to wave 2`() throws {
        let a = Package.Manifest(
            name: "swift-a",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [
                .init(source: .path("../swift-b"), name: "swift-b", products: ["B"]),
                .init(source: .path("../swift-c"), name: "swift-c", products: ["C"]),
            ]
        )
        let b = Package.Manifest(
            name: "swift-b",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [
                .init(source: .path("../swift-d"), name: "swift-d", products: ["D"])
            ]
        )
        let c = Package.Manifest(
            name: "swift-c",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [
                .init(source: .path("../swift-d"), name: "swift-d", products: ["D"])
            ]
        )
        let d = Package.Manifest(name: "swift-d", toolsVersion: Version.Tools(major: 6, minor: 3))

        let workspace = Package.Workspace(root: "/tmp", manifests: [a, b, c, d])
        let graph = try Package.Graph(workspace)

        #expect(graph.directDependents(of: "swift-d") == ["swift-b", "swift-c"])

        let waves = graph.transitiveDependents(of: "swift-d", depth: .max)
        #expect(waves.count == 2)
        #expect(waves[0].packages == ["swift-b", "swift-c"])
        #expect(waves[1].packages == ["swift-a"])
    }

    @Test
    func `Depth limit truncates wave list`() throws {

        let manifests: [Package.Manifest] = [
            .init(
                name: "a",
                toolsVersion: Version.Tools(major: 6, minor: 3),
                dependencies: [.init(source: .path("../b"), name: "b", products: ["B"])]
            ),
            .init(
                name: "b",
                toolsVersion: Version.Tools(major: 6, minor: 3),
                dependencies: [.init(source: .path("../c"), name: "c", products: ["C"])]
            ),
            .init(
                name: "c",
                toolsVersion: Version.Tools(major: 6, minor: 3),
                dependencies: [.init(source: .path("../d"), name: "d", products: ["D"])]
            ),
            .init(name: "d", toolsVersion: Version.Tools(major: 6, minor: 3)),
        ]
        let workspace = Package.Workspace(root: "/tmp", manifests: manifests)
        let graph = try Package.Graph(workspace)

        let waves1 = graph.transitiveDependents(of: "d", depth: 1)
        #expect(waves1.count == 1)
        #expect(waves1[0].packages == ["c"])

        let waves2 = graph.transitiveDependents(of: "d", depth: 2)
        #expect(waves2.count == 2)

        let wavesAll = graph.transitiveDependents(of: "d", depth: .max)
        #expect(wavesAll.count == 3)
    }

    @Test
    func `Empty graph: structural queries return empty results`() throws {
        let workspace = Package.Workspace(root: "/tmp", manifests: [])
        let graph = try Package.Graph(workspace)

        #expect(graph.cycles().isEmpty)
        let topo = try graph.topologicalOrder()
        #expect(topo.isEmpty)
        #expect(graph.stronglyConnectedComponents().isEmpty)
        #expect(graph.dot() == "digraph PackageGraph {\n}\n")
    }

    @Test
    func `Topological order: linear chain returns dependencies first`() throws {

        let root = Package.Manifest(
            name: "swift-root",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [
                .init(source: .path("../swift-middle"), name: "swift-middle", products: ["Middle"])
            ]
        )
        let middle = Package.Manifest(
            name: "swift-middle",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [
                .init(source: .path("../swift-leaf"), name: "swift-leaf", products: ["Leaf"])
            ]
        )
        let leaf = Package.Manifest(name: "swift-leaf", toolsVersion: Version.Tools(major: 6, minor: 3))

        let workspace = Package.Workspace(root: "/tmp", manifests: [root, middle, leaf])
        let graph = try Package.Graph(workspace)

        let order = try graph.topologicalOrder()
        #expect(order == ["swift-leaf", "swift-middle", "swift-root"])
    }

    @Test
    func `Topological order: diamond honors dependency precedence`() throws {

        let a = Package.Manifest(
            name: "a",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [
                .init(source: .path("../b"), name: "b", products: ["B"]),
                .init(source: .path("../c"), name: "c", products: ["C"]),
            ]
        )
        let b = Package.Manifest(
            name: "b",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [.init(source: .path("../d"), name: "d", products: ["D"])]
        )
        let c = Package.Manifest(
            name: "c",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [.init(source: .path("../d"), name: "d", products: ["D"])]
        )
        let d = Package.Manifest(name: "d", toolsVersion: Version.Tools(major: 6, minor: 3))

        let workspace = Package.Workspace(root: "/tmp", manifests: [a, b, c, d])
        let graph = try Package.Graph(workspace)

        let order = try graph.topologicalOrder()
        let aIdx = order.firstIndex(of: "a")!
        let bIdx = order.firstIndex(of: "b")!
        let cIdx = order.firstIndex(of: "c")!
        let dIdx = order.firstIndex(of: "d")!

        #expect(dIdx < bIdx)
        #expect(dIdx < cIdx)
        #expect(bIdx < aIdx)
        #expect(cIdx < aIdx)
    }

    @Test
    func `Topological order: cycle throws cycleDetected`() throws {

        let a = Package.Manifest(
            name: "a",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [.init(source: .path("../b"), name: "b", products: ["B"])]
        )
        let b = Package.Manifest(
            name: "b",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [.init(source: .path("../a"), name: "a", products: ["A"])]
        )

        let workspace = Package.Workspace(root: "/tmp", manifests: [a, b])
        let graph = try Package.Graph(workspace)

        #expect(throws: Package.Graph.Error.self) {
            _ = try graph.topologicalOrder()
        }

        do throws(Package.Graph.Error) {
            _ = try graph.topologicalOrder()
            Issue.record("expected cycleDetected error")
        } catch {
            #expect(error.kind == .cycleDetected)
        }
    }

    @Test
    func `Cycles: acyclic graph returns empty`() throws {
        let leaf = Package.Manifest(name: "leaf", toolsVersion: Version.Tools(major: 6, minor: 3))
        let root = Package.Manifest(
            name: "root",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [.init(source: .path("../leaf"), name: "leaf", products: ["Leaf"])]
        )
        let workspace = Package.Workspace(root: "/tmp", manifests: [root, leaf])
        let graph = try Package.Graph(workspace)

        #expect(graph.cycles().isEmpty)
    }

    @Test
    func `Cycles: two-node cycle is reported`() throws {

        let a = Package.Manifest(
            name: "a",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [.init(source: .path("../b"), name: "b", products: ["B"])]
        )
        let b = Package.Manifest(
            name: "b",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [.init(source: .path("../a"), name: "a", products: ["A"])]
        )
        let workspace = Package.Workspace(root: "/tmp", manifests: [a, b])
        let graph = try Package.Graph(workspace)

        let cycles = graph.cycles()
        #expect(cycles.count == 1)
        #expect(cycles[0].nodes == ["a", "b"])
    }

    @Test
    func `Cycles: self-loop is reported`() throws {

        let a = Package.Manifest(
            name: "a",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [.init(source: .path("./a"), name: "a", products: ["A"])]
        )
        let workspace = Package.Workspace(root: "/tmp", manifests: [a])
        let graph = try Package.Graph(workspace)

        let cycles = graph.cycles()
        #expect(cycles.count == 1)
        #expect(cycles[0].nodes == ["a"])
    }

    @Test
    func `SCC: linear chain yields singleton components`() throws {
        let leaf = Package.Manifest(name: "leaf", toolsVersion: Version.Tools(major: 6, minor: 3))
        let middle = Package.Manifest(
            name: "middle",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [.init(source: .path("../leaf"), name: "leaf", products: ["Leaf"])]
        )
        let root = Package.Manifest(
            name: "root",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [.init(source: .path("../middle"), name: "middle", products: ["Middle"])]
        )

        let workspace = Package.Workspace(root: "/tmp", manifests: [root, middle, leaf])
        let graph = try Package.Graph(workspace)

        let sccs = graph.stronglyConnectedComponents()
        #expect(sccs.count == 3)
        #expect(sccs.allSatisfy { $0.count == 1 })

        let flat = Swift.Set(sccs.flatMap { $0 })
        #expect(flat == ["leaf", "middle", "root"])
    }

    @Test
    func `SCC: two-cycle yields one component`() throws {
        let a = Package.Manifest(
            name: "a",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [.init(source: .path("../b"), name: "b", products: ["B"])]
        )
        let b = Package.Manifest(
            name: "b",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [.init(source: .path("../a"), name: "a", products: ["A"])]
        )
        let workspace = Package.Workspace(root: "/tmp", manifests: [a, b])
        let graph = try Package.Graph(workspace)

        let sccs = graph.stronglyConnectedComponents()
        #expect(sccs.count == 1)
        #expect(sccs[0] == ["a", "b"])
    }

    @Test
    func `DOT: linear chain emits sorted nodes and edges`() throws {
        let leaf = Package.Manifest(name: "swift-leaf", toolsVersion: Version.Tools(major: 6, minor: 3))
        let root = Package.Manifest(
            name: "swift-root",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [
                .init(source: .path("../swift-leaf"), name: "swift-leaf", products: ["Leaf"])
            ]
        )
        let workspace = Package.Workspace(root: "/tmp", manifests: [root, leaf])
        let graph = try Package.Graph(workspace)

        let expected = """
            digraph PackageGraph {
              "swift-leaf";
              "swift-root";
              "swift-root" -> "swift-leaf";
            }

            """
        #expect(graph.dot() == expected)
    }

    @Test
    func `DOT: external dependencies are omitted`() throws {

        let local = Package.Manifest(
            name: "local",
            toolsVersion: Version.Tools(major: 6, minor: 3),
            dependencies: [
                .init(
                    source: .url("https://example.invalid/external", from: Version.Semantic(major: 1, minor: 0, patch: 0)),
                    name: "external",
                    products: ["External"]
                )
            ]
        )
        let workspace = Package.Workspace(root: "/tmp", manifests: [local])
        let graph = try Package.Graph(workspace)

        let expected = """
            digraph PackageGraph {
              "local";
            }

            """
        #expect(graph.dot() == expected)
    }
}
