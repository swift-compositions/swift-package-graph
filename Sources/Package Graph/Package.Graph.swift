internal import Graph

extension Package {

    public struct Graph: ~Copyable, Swift.Sendable {
        @usableFromInline
        internal let manifestByName: [Package.Name: Package.Manifest]

        @usableFromInline
        internal let forwardAdjacency: [Package.Name: Swift.Set<Package.Name>]

        @usableFromInline
        internal let reverseAdjacency: [Package.Name: Swift.Set<Package.Name>]

        internal let sequential: Graph::Graph.Sequential<NodeIdentity, Package.Manifest>

        internal let nodeByName: [Package.Name: Graph::Graph.Node<NodeIdentity>]

        internal let nameByNode: [Graph::Graph.Node<NodeIdentity>: Package.Name]

        public init(_ workspace: borrowing Workspace) throws(Self.Error) {
            var manifestByName: [Package.Name: Package.Manifest] = [:]
            var forwardAdjacency: [Package.Name: Swift.Set<Package.Name>] = [:]
            var reverseAdjacency: [Package.Name: Swift.Set<Package.Name>] = [:]
            var nodeByName: [Package.Name: Graph::Graph.Node<NodeIdentity>] = [:]
            var nameByNode: [Graph::Graph.Node<NodeIdentity>: Package.Name] = [:]
            var builder = Graph::Graph.Sequential<NodeIdentity, Package.Manifest>.Builder()

            for manifest in workspace.manifests {
                manifestByName[manifest.name] = manifest
                let node = builder.allocate(manifest)
                nodeByName[manifest.name] = node
                nameByNode[node] = manifest.name

                var deps = Swift.Set<Package.Name>()
                for dependency in manifest.dependencies {
                    let depName = dependency.name
                    deps.insert(depName)
                    reverseAdjacency[depName, default: []].insert(manifest.name)
                }
                forwardAdjacency[manifest.name] = deps
            }

            self.manifestByName = manifestByName
            self.forwardAdjacency = forwardAdjacency
            self.reverseAdjacency = reverseAdjacency
            self.sequential = builder.build()
            self.nodeByName = nodeByName
            self.nameByNode = nameByNode
        }
    }
}

extension Package.Graph {

    public func directDependencies(of package: Package.Name) -> Swift.Set<Package.Name> {
        forwardAdjacency[package] ?? []
    }

    public func transitiveDependencies(of package: Package.Name) -> Swift.Set<Package.Name> {
        var visited: Swift.Set<Package.Name> = []
        var frontier: Swift.Set<Package.Name> = directDependencies(of: package)
        while let next = frontier.first {
            frontier.remove(next)
            guard !visited.contains(next) else { continue }
            visited.insert(next)
            for downstream in directDependencies(of: next) where !visited.contains(downstream) {
                frontier.insert(downstream)
            }
        }
        return visited
    }
}

extension Package.Graph {

    public func directDependents(of package: Package.Name) -> Swift.Set<Package.Name> {
        reverseAdjacency[package] ?? []
    }

    public func transitiveDependents(of package: Package.Name, depth: Swift.Int = .max) -> [Wave] {
        guard depth >= 1 else { return [] }

        var waves: [Wave] = []
        var visited: Swift.Set<Package.Name> = [package]
        var current: Swift.Set<Package.Name> = directDependents(of: package)

        var d = 1
        while !current.isEmpty, d <= depth {

            let waveNodes = current.subtracting(visited)
            guard !waveNodes.isEmpty else { break }
            waves.append(Wave(depth: d, packages: waveNodes))
            visited.formUnion(waveNodes)

            var next: Swift.Set<Package.Name> = []
            for node in waveNodes {
                for upstream in directDependents(of: node) where !visited.contains(upstream) {
                    next.insert(upstream)
                }
            }
            current = next
            d += 1
        }

        return waves
    }
}

extension Package.Graph {

    public func manifest(for package: Package.Name) -> Package.Manifest? {
        manifestByName[package]
    }

    public var packages: Swift.Set<Package.Name> {
        Swift.Set(manifestByName.keys)
    }
}

extension Package.Graph {

    internal func makeAdjacencyExtract()
        -> Graph::Graph.Adjacency.Extract<
            Package.Manifest,
            NodeIdentity,
            [Graph::Graph.Node<NodeIdentity>]
        >
    {
        let nodeByName = self.nodeByName
        return .init { manifest in
            manifest.dependencies.compactMap { nodeByName[$0.name] }
        }
    }

    public func cycles() -> [Cycle] {
        let groups = sequential.analyze(using: makeAdjacencyExtract()).scc()
        var result: [Cycle] = []
        for group in groups {
            let names = group.compactMap { nameByNode[$0] }.sorted()
            if names.count >= 2 {
                result.append(Cycle(nodes: names))
            } else if names.count == 1, forwardAdjacency[names[0]]?.contains(names[0]) == true {
                result.append(Cycle(nodes: names))
            }
        }
        return result.sorted { $0.nodes.lexicographicallyPrecedes($1.nodes) }
    }

    public func topologicalOrder() throws(Self.Error) -> [Package.Name] {
        let traversal = sequential.traverse.topological(using: makeAdjacencyExtract())
        guard !traversal.hasCycles else {
            throw .init(
                kind: .cycleDetected,
                detail: "graph contains dependency cycles; call cycles() to enumerate"
            )
        }

        let names = traversal.compactMap { nameByNode[$0.node] }
        return Swift.Array(names.reversed())
    }

    public func stronglyConnectedComponents() -> [[Package.Name]] {
        let groups = sequential.analyze(using: makeAdjacencyExtract()).scc()
        return groups.map { group in
            group.compactMap { nameByNode[$0] }.sorted()
        }
    }

    public func dot() -> Swift.String {
        let sortedNames = manifestByName.keys.sorted()
        var output = "digraph PackageGraph {\n"
        for name in sortedNames {
            output += "  \"\(name.underlying)\";\n"
        }
        for source in sortedNames {
            guard let targets = forwardAdjacency[source] else { continue }
            for target in targets.sorted() where manifestByName[target] != nil {
                output += "  \"\(source.underlying)\" -> \"\(target.underlying)\";\n"
            }
        }
        output += "}\n"
        return output
    }
}
