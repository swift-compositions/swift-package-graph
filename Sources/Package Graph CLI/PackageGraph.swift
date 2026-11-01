internal import Command
internal import File_System
internal import Package_Graph
internal import Package_Graph_Rewrite
internal import Path

#if canImport(Darwin)
    internal import Darwin
#elseif canImport(Glibc)
    internal import Glibc
#elseif canImport(Musl)
    internal import Musl
#elseif canImport(WinSDK)
    internal import WinSDK
#endif

enum PackageGraph: Command.`Protocol`, Equatable {
    case list(List)
    case topo(Topo)
    case cycles(Cycles)
    case scc(SCC)
    case dot(Dot)
    case dependentsOf(DependentsOf)
    case dependenciesOf(DependenciesOf)
    case traitMismatches(TraitMismatches)
    case rewrite(Rewrite)
}

extension PackageGraph {
    static var configuration: Command.Configuration {
        Command.Configuration(
            name: "package-graph",
            abstract: "Inspect SwiftPM package dependency graphs."
        )
    }

    static var schema: Command.Schema.Definition<Self> {
        Command.Schema.Definition<Self> {
            Command.Subcommand.Group {
                Command.Subcommand.Case(
                    "list",
                    help: .init(abstract: "List discovered packages."),
                    initial: { List() },
                    map: Self.list
                )
                Command.Subcommand.Case(
                    "topo",
                    help: .init(abstract: "Topological order (dependencies first)."),
                    initial: { Topo() },
                    map: Self.topo
                )
                Command.Subcommand.Case(
                    "cycles",
                    help: .init(abstract: "List dependency cycles."),
                    initial: { Cycles() },
                    map: Self.cycles
                )
                Command.Subcommand.Case(
                    "scc",
                    help: .init(abstract: "Strongly connected components."),
                    initial: { SCC() },
                    map: Self.scc
                )
                Command.Subcommand.Case(
                    "dot",
                    help: .init(abstract: "Emit GraphViz DOT."),
                    initial: { Dot() },
                    map: Self.dot
                )
                Command.Subcommand.Case(
                    "dependents-of",
                    help: .init(abstract: "List packages depending on <package>."),
                    initial: { DependentsOf() },
                    map: Self.dependentsOf
                )
                Command.Subcommand.Case(
                    "dependencies-of",
                    help: .init(abstract: "List packages <package> depends on."),
                    initial: { DependenciesOf() },
                    map: Self.dependenciesOf
                )
                Command.Subcommand.Case(
                    "trait-mismatches",
                    help: .init(abstract: "List trait requests the resolver never sees (#10749)."),
                    initial: { TraitMismatches() },
                    map: Self.traitMismatches
                )
                Command.Subcommand.Case(
                    "rewrite",
                    help: .init(abstract: "Version branch dependencies and drop root trait unions (dry run unless --write)."),
                    initial: { Rewrite() },
                    map: Self.rewrite
                )
            }
        }
    }

    mutating func run() async throws(Command.Error) {
        switch self {
        case .list(var c):
            try await c.run()
            self = .list(c)

        case .topo(var c):
            try await c.run()
            self = .topo(c)

        case .cycles(var c):
            try await c.run()
            self = .cycles(c)

        case .scc(var c):
            try await c.run()
            self = .scc(c)

        case .dot(var c):
            try await c.run()
            self = .dot(c)

        case .dependentsOf(var c):
            try await c.run()
            self = .dependentsOf(c)

        case .dependenciesOf(var c):
            try await c.run()
            self = .dependenciesOf(c)

        case .traitMismatches(var c):
            try await c.run()
            self = .traitMismatches(c)

        case .rewrite(var c):
            try await c.run()
            self = .rewrite(c)
        }
    }
}

extension PackageGraph {

    fileprivate static func loadGraph(at root: Path::Path) async -> Package.Graph {
        do {
            let workspace = try await Package.Workspace.discover(at: root)
            return try Package.Graph(workspace)
        } catch let error as Package.Workspace.Error {
            printError("package-graph: workspace error (\(error.kind)): \(error.detail)")
            platformExit(2)
        } catch let error as Package.Graph.Error {
            printError("package-graph: graph error: \(error)")
            platformExit(3)
        } catch {
            printError("package-graph: \(error)")
            platformExit(4)
        }
    }

    fileprivate static func resolveRoot(_ override: Swift.String) -> Path::Path {
        let rootString: Swift.String
        if override.isEmpty {
            rootString = unsafe currentWorkingDirectory()
        } else {
            rootString = override
        }
        do throws(Path::Path.Error) {
            return try Path::Path(rootString)
        } catch {
            printError("package-graph: invalid root path '\(rootString)': \(error)")
            platformExit(2)
        }
    }

    @unsafe
    fileprivate static func currentWorkingDirectory() -> Swift.String {
        var buffer = [CChar](repeating: 0, count: 4096)

        let cwd = unsafe getcwd(&buffer, numericCast(buffer.count))
        guard let cwdPtr = unsafe cwd else { return "." }
        return unsafe Swift.String(cString: cwdPtr)
    }

    fileprivate static func printError(_ message: Swift.String) {

        print(message)
    }

    fileprivate static func platformExit(_ code: Swift.Int32) -> Never {
        exit(code)
    }
}

private enum Names {}

extension Names {
    static let root: Argument.Name = .long(Argument.Name.Long(_unchecked: "root"))
    static let depth: Argument.Name = .long(Argument.Name.Long(_unchecked: "depth"))
    static let search: Argument.Name = .long(Argument.Name.Long(_unchecked: "search-depth"))
    static let version: Argument.Name = .long(Argument.Name.Long(_unchecked: "version"))
    static let write: Argument.Name = .long(Argument.Name.Long(_unchecked: "write"))
    static let organizations: Argument.Name = .long(Argument.Name.Long(_unchecked: "organizations"))
}

extension PackageGraph {
    struct List: Command.`Protocol`, Equatable {
        var root: Swift.String

        init(root: Swift.String = "") {
            self.root = root
        }
    }

    struct Topo: Command.`Protocol`, Equatable {
        var root: Swift.String

        init(root: Swift.String = "") {
            self.root = root
        }
    }

    struct Cycles: Command.`Protocol`, Equatable {
        var root: Swift.String

        init(root: Swift.String = "") {
            self.root = root
        }
    }

    struct SCC: Command.`Protocol`, Equatable {
        var root: Swift.String

        init(root: Swift.String = "") {
            self.root = root
        }
    }

    struct Dot: Command.`Protocol`, Equatable {
        var root: Swift.String

        init(root: Swift.String = "") {
            self.root = root
        }
    }

    struct DependentsOf: Command.`Protocol`, Equatable {
        var package: Swift.String
        var root: Swift.String
        var depth: Swift.Int

        init(
            package: Swift.String = "",
            root: Swift.String = "",
            depth: Swift.Int = Swift.Int.max
        ) {
            self.package = package
            self.root = root
            self.depth = depth
        }
    }

    struct DependenciesOf: Command.`Protocol`, Equatable {
        var package: Swift.String
        var root: Swift.String

        init(
            package: Swift.String = "",
            root: Swift.String = ""
        ) {
            self.package = package
            self.root = root
        }
    }
}

extension PackageGraph.List {
    static var configuration: Command.Configuration {
        Command.Configuration(
            name: "list",
            abstract: "List discovered packages."
        )
    }

    static var schema: Command.Schema.Definition<Self> {
        Command.Schema.Definition<Self> {
            Command.Option(
                \.root,
                name: Names.root,
                help: .init(abstract: "Workspace root (default $PWD).")
            )
        }
    }

    mutating func run() async throws(Command.Error) {
        let rootPath = PackageGraph.resolveRoot(root)
        let graph = await PackageGraph.loadGraph(at: rootPath)
        for name in graph.packages.sorted() {
            print(name)
        }
    }
}

extension PackageGraph.Topo {
    static var configuration: Command.Configuration {
        Command.Configuration(
            name: "topo",
            abstract: "Topological order (dependencies first)."
        )
    }

    static var schema: Command.Schema.Definition<Self> {
        Command.Schema.Definition<Self> {
            Command.Option(
                \.root,
                name: Names.root,
                help: .init(abstract: "Workspace root (default $PWD).")
            )
        }
    }

    mutating func run() async throws(Command.Error) {
        let rootPath = PackageGraph.resolveRoot(root)
        let graph = await PackageGraph.loadGraph(at: rootPath)
        do throws(Package.Graph.Error) {
            let order = try graph.topologicalOrder()
            for name in order {
                print(name)
            }
        } catch {
            PackageGraph.printError("package-graph: graph error: \(error)")
            PackageGraph.platformExit(3)
        }
    }
}

extension PackageGraph.Cycles {
    static var configuration: Command.Configuration {
        Command.Configuration(
            name: "cycles",
            abstract: "List dependency cycles."
        )
    }

    static var schema: Command.Schema.Definition<Self> {
        Command.Schema.Definition<Self> {
            Command.Option(
                \.root,
                name: Names.root,
                help: .init(abstract: "Workspace root (default $PWD).")
            )
        }
    }

    mutating func run() async throws(Command.Error) {
        let rootPath = PackageGraph.resolveRoot(root)
        let graph = await PackageGraph.loadGraph(at: rootPath)
        let cycles = graph.cycles()
        if cycles.isEmpty {
            print("(no cycles)")
        } else {
            for cycle in cycles {
                print(cycle.nodes.map { "\($0)" }.joined(separator: " -> "))
            }
        }
    }
}

extension PackageGraph.SCC {
    static var configuration: Command.Configuration {
        Command.Configuration(
            name: "scc",
            abstract: "Strongly connected components."
        )
    }

    static var schema: Command.Schema.Definition<Self> {
        Command.Schema.Definition<Self> {
            Command.Option(
                \.root,
                name: Names.root,
                help: .init(abstract: "Workspace root (default $PWD).")
            )
        }
    }

    mutating func run() async throws(Command.Error) {
        let rootPath = PackageGraph.resolveRoot(root)
        let graph = await PackageGraph.loadGraph(at: rootPath)
        let components = graph.stronglyConnectedComponents()
        for component in components {
            print(component.map { "\($0)" }.sorted().joined(separator: ", "))
        }
    }
}

extension PackageGraph.Dot {
    static var configuration: Command.Configuration {
        Command.Configuration(
            name: "dot",
            abstract: "Emit GraphViz DOT."
        )
    }

    static var schema: Command.Schema.Definition<Self> {
        Command.Schema.Definition<Self> {
            Command.Option(
                \.root,
                name: Names.root,
                help: .init(abstract: "Workspace root (default $PWD).")
            )
        }
    }

    mutating func run() async throws(Command.Error) {
        let rootPath = PackageGraph.resolveRoot(root)
        let graph = await PackageGraph.loadGraph(at: rootPath)
        print(graph.dot())
    }
}

extension PackageGraph.DependentsOf {
    static var configuration: Command.Configuration {
        Command.Configuration(
            name: "dependents-of",
            abstract: "List packages depending on <package>."
        )
    }

    static var schema: Command.Schema.Definition<Self> {
        Command.Schema.Definition<Self> {
            Command.Positional(
                \.package,
                name: "package",
                help: .init(abstract: "Upstream package name.")
            )
            Command.Option(
                \.root,
                name: Names.root,
                help: .init(abstract: "Workspace root (default $PWD).")
            )
            Command.Option(
                \.depth,
                name: Names.depth,
                help: .init(abstract: "Wave depth (default .max).")
            )
        }
    }

    mutating func run() async throws(Command.Error) {
        let rootPath = PackageGraph.resolveRoot(root)
        let graph = await PackageGraph.loadGraph(at: rootPath)
        let waves = graph.transitiveDependents(
            of: Package.Name(_unchecked: package),
            depth: depth
        )
        for wave in waves {
            for name in wave.packages.sorted() {
                print("[\(wave.depth)] \(name)")
            }
        }
    }
}

extension PackageGraph.DependenciesOf {
    static var configuration: Command.Configuration {
        Command.Configuration(
            name: "dependencies-of",
            abstract: "List packages <package> depends on."
        )
    }

    static var schema: Command.Schema.Definition<Self> {
        Command.Schema.Definition<Self> {
            Command.Positional(
                \.package,
                name: "package",
                help: .init(abstract: "Downstream package name.")
            )
            Command.Option(
                \.root,
                name: Names.root,
                help: .init(abstract: "Workspace root (default $PWD).")
            )
        }
    }

    mutating func run() async throws(Command.Error) {
        let rootPath = PackageGraph.resolveRoot(root)
        let graph = await PackageGraph.loadGraph(at: rootPath)
        let dependencies = graph.transitiveDependencies(
            of: Package.Name(_unchecked: package)
        )
        for name in dependencies.sorted() {
            print(name)
        }
    }
}

@main
enum Main {}

extension Main {
    static func main() async {
        let argv = Array(CommandLine.arguments.dropFirst())
        do throws(Command.Error) {
            var cmd = try Command.parse(
                PackageGraph.self,
                from: argv,
                initial: .list(.init())
            )
            try await cmd.run()
        } catch {
            handle(error)
        }
    }

    private static func handle(_ error: Command.Error) -> Never {
        switch error {
        case .helpRequested:

            var buffer = ""
            Command.Help<PackageGraph>().serialize(PackageGraph.schema, into: &buffer)
            print(buffer)
            exit(0)

        case .helpRequestedForSubcommand(_, let rendered):
            print(rendered)
            exit(0)

        case .missingSubcommand(let available):
            print(
                "package-graph: missing subcommand. Expected one of: \(available.joined(separator: ", "))"
            )
            exit(64)

        case .versionRequested(let version):
            print(version)
            exit(0)

        case .exit(let code, let message):
            if let message { print(message) }
            exit(code)

        case .invalidEnvironmentValue(let name, let environment, let value):
            print(
                "package-graph: invalid value '\(value)' for '\(name)' from environment variable '\(environment)'"
            )
            exit(64)

        case .unknownSubcommand(let name, _, _):
            print("package-graph: unknown subcommand '\(name)'")
            exit(64)

        case .unknownLongOption(let name, _, _):
            print("package-graph: unknown option '--\(name)'")
            exit(64)

        case .unknownShortOption(let name, _):
            print("package-graph: unknown option '-\(name)'")
            exit(64)

        case .missingOptionValue(let name, _):
            print("package-graph: option '--\(name)' requires a value")
            exit(64)

        case .invalidValue(let name, let value, _):
            print("package-graph: invalid value '\(value)' for option '\(name)'")
            exit(64)

        case .missingPositional(let name, _):
            print("package-graph: missing required argument '\(name)'")
            exit(64)

        case .unexpectedPositional(let value, _):
            print("package-graph: unexpected argument '\(value)'")
            exit(64)

        case .validationFailed(let reason):
            print("package-graph: \(reason)")
            exit(64)

        case .argument(let error):
            print("package-graph: \(error)")
            exit(64)

        case .tokenizer(let reason, _):
            print("package-graph: \(reason)")
            exit(64)
        }
    }
}

extension PackageGraph {
    struct TraitMismatches: Command.`Protocol`, Equatable {
        var root: Swift.String
        var depth: Swift.Int

        init(root: Swift.String = "", depth: Swift.Int = 3) {
            self.root = root
            self.depth = depth
        }
    }
}

extension PackageGraph.TraitMismatches {
    static var configuration: Command.Configuration {
        Command.Configuration(
            name: "trait-mismatches",
            abstract: "List trait requests the resolver never sees (#10749)."
        )
    }

    static var schema: Command.Schema.Definition<Self> {
        Command.Schema.Definition<Self> {
            Command.Option(
                \.root,
                name: Names.root,
                help: .init(abstract: "Workspace root (default $PWD).")
            )
            Command.Option(
                \.depth,
                name: Names.search,
                help: .init(abstract: "How many directory levels below the root to search for packages (default 3).")
            )
        }
    }

    /// Prints one line per mismatch and exits 1 when any mismatch misses a dependency or any
    /// manifest could not be evaluated.
    mutating func run() async throws(Command.Error) {
        let rootPath = PackageGraph.resolveRoot(root)
        let evaluations: [Package.Manifest.Evaluation]
        let failures: [Path::Path]
        do throws(Package.Workspace.Error) {
            let loaded = try await Package.Workspace.evaluations(
                at: rootPath,
                configuration: .init(maxDepth: depth)
            )
            evaluations = loaded.evaluations.map(\.evaluation)
            failures = loaded.failures
        } catch {
            PackageGraph.printError("package-graph: workspace error (\(error.kind)): \(error.detail)")
            PackageGraph.platformExit(2)
        }
        let mismatches = Package.Trait.Mismatch.all(in: evaluations)
        var missing = 0
        for mismatch in mismatches {
            let traits = mismatch.traits.map(\.name).joined(separator: ", ")
            let kind: Swift.String
            switch mismatch.kind {
            case .unused:
                kind = "unused"
            case .guarded(let guards):
                kind = "used only under \(guards.sorted().joined(separator: ", "))"
            }
            let consequences: Swift.String
            switch mismatch.consequences {
            case nil:
                consequences = "dependency not in workspace"
            case let identities? where identities.isEmpty:
                consequences = "misses nothing"
            case let identities?:
                missing += 1
                consequences = "misses \(identities.map(\.underlying).joined(separator: ", "))"
            }
            print("\(mismatch.package.underlying) -> \(mismatch.dependency.underlying) [\(traits)]: \(kind); \(consequences)")
        }
        for failure in failures {
            print("not evaluated: \(failure.string)")
        }
        print(
            "\(evaluations.count) packages, \(failures.count) not evaluated, \(mismatches.count) mismatches, \(missing) that miss a dependency"
        )
        if missing > 0 || !failures.isEmpty {
            PackageGraph.platformExit(1)
        }
    }
}

extension PackageGraph {
    struct Rewrite: Command.`Protocol`, Equatable {
        var root: Swift.String
        var depth: Swift.Int
        var version: Swift.String
        var organizations: Swift.String
        var write: Swift.Bool

        init(
            root: Swift.String = "",
            depth: Swift.Int = 3,
            version: Swift.String = "0.0.100",
            organizations: Swift.String = "",
            write: Swift.Bool = false
        ) {
            self.root = root
            self.depth = depth
            self.version = version
            self.organizations = organizations
            self.write = write
        }
    }
}

extension PackageGraph.Rewrite {
    static var configuration: Command.Configuration {
        Command.Configuration(
            name: "rewrite",
            abstract: "Version branch dependencies and drop root trait unions (dry run unless --write)."
        )
    }

    static var schema: Command.Schema.Definition<Self> {
        Command.Schema.Definition<Self> {
            Command.Option(
                \.root,
                name: Names.root,
                help: .init(abstract: "Workspace root (default $PWD).")
            )
            Command.Option(
                \.depth,
                name: Names.search,
                help: .init(abstract: "How many directory levels below the root to search for packages (default 3).")
            )
            Command.Option(
                \.version,
                name: Names.version,
                help: .init(abstract: "The development version required with .upToNextMinor(from:) (default 0.0.100).")
            )
            Command.Option(
                \.organizations,
                name: Names.organizations,
                help: .init(
                    abstract: "The organizations to version, as the JSON array `institute organizations` prints (required)."
                )
            )
            Command.Flag(
                \.write,
                name: Names.write,
                help: .init(abstract: "Write the rewritten manifests; without it, only report.")
            )
        }
    }

    /// Prints one line per package it changes or cannot finish, and exits 1 when a manifest could
    /// not be evaluated, read or written, or when a branch dependency was left unreached.
    mutating func run() async throws(Command.Error) {
        guard let organizations = Package.Manifest.Rewrite.organizations(parsing: organizations) else {
            PackageGraph.printError(
                "package-graph: --organizations must be a non-empty JSON array of organization names, "
                    + "as `institute organizations` prints"
            )
            PackageGraph.platformExit(64)
        }
        let rootPath = PackageGraph.resolveRoot(root)
        let loaded: (evaluations: [(directory: Path::Path, evaluation: Package.Manifest.Evaluation)], failures: [Path::Path])
        do throws(Package.Workspace.Error) {
            loaded = try await Package.Workspace.evaluations(at: rootPath, configuration: .init(maxDepth: depth))
        } catch {
            PackageGraph.printError("package-graph: workspace error (\(error.kind)): \(error.detail)")
            PackageGraph.platformExit(2)
        }
        let mismatches = Package.Trait.Mismatch.all(in: loaded.evaluations.map(\.evaluation))
        var problems = loaded.failures.count
        var totals = (packages: 0, versioned: 0, removed: 0, conditioned: 0, retained: 0)
        for failure in loaded.failures {
            print("not evaluated: \(failure.string)")
        }
        for (directory, evaluation) in loaded.evaluations {
            let plan = Package.Manifest.Rewrite(
                evaluation: evaluation,
                mismatches: mismatches,
                version: version,
                organizations: organizations
            )
            let path = directory / "Package.swift"
            let source: Swift.String
            do throws(Either<File.System.Read.Full.Error, Never>) {
                source = try File(path).read.full { bytes in
                    var storage: [Byte] = []
                    storage.reserveCapacity(bytes.count)
                    for index in bytes.indices { storage.append(bytes[index]) }
                    return Swift.String(decoding: storage, as: Swift.UTF8.self)
                }
            } catch {
                print("not read: \(path.string): \(error)")
                problems += 1
                continue
            }
            let outcome = plan.apply(to: source)
            var notes: [Swift.String] = []
            if outcome.versioned > 0 { notes.append("versioned \(outcome.versioned)") }
            if !outcome.removed.isEmpty { notes.append("removed \(outcome.removed.sorted().joined(separator: ", "))") }
            if !outcome.conditioned.isEmpty { notes.append("conditioned \(outcome.conditioned.sorted().joined(separator: ", "))") }
            if !plan.retained.isEmpty { notes.append("left for a nested test package: \(plan.retained.sorted().joined(separator: ", "))") }
            if !outcome.unreached.isEmpty {
                notes.append("UNREACHED \(outcome.unreached.sorted().joined(separator: ", "))")
                problems += 1
            }
            if outcome.source != source {
                totals.packages += 1
                if write {
                    do throws(File.System.Write.Atomic.Error) {
                        try File(path).write.atomic(outcome.source)
                    } catch {
                        print("not written: \(path.string): \(error)")
                        problems += 1
                        continue
                    }
                }
            }
            totals.versioned += outcome.versioned
            totals.removed += outcome.removed.count
            totals.conditioned += outcome.conditioned.count
            totals.retained += plan.retained.count
            if !notes.isEmpty {
                print("\(evaluation.name.underlying): \(notes.joined(separator: "; "))")
            }
        }
        print(
            "\(loaded.evaluations.count) packages, \(totals.packages) changed\(write ? "" : " (dry run)"), \(totals.versioned) versioned, \(totals.removed) removed, \(totals.conditioned) conditioned, \(totals.retained) left for nested test packages, \(problems) problems"
        )
        if problems > 0 {
            PackageGraph.platformExit(1)
        }
    }
}
