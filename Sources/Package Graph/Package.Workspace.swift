internal import File_System
private import Package_Manager

extension Package {

    public struct Workspace: ~Copyable, Swift.Sendable {

        public let root: Paths.Path

        public let manifests: [Package.Manifest]

        public init(root: Paths.Path, manifests: [Package.Manifest]) {
            self.root = root
            self.manifests = manifests
        }
    }
}

extension Package.Workspace {

    public static func discover(
        at root: Paths.Path,
        configuration: Configuration = .init()
    ) async throws(Self.Error) -> Self {
        guard directoryExists(at: root) else {
            throw .init(kind: .rootDoesNotExist, detail: root.string)
        }

        let packageDirectories = findPackageDirectories(
            under: root,
            maxDepth: configuration.maxDepth
        )

        guard !packageDirectories.isEmpty else {
            throw .init(
                kind: .noPackagesFound,
                detail:
                    "no Package.swift found within depth \(configuration.maxDepth) of \(root.string)"
            )
        }

        let swiftExecutable = configuration.swiftExecutable?.string ?? Package.Manager.launcher
        let concurrencyBound = Swift.max(1, configuration.maxConcurrentLoads)

        let manifests = try await loadManifests(
            packageDirectories: packageDirectories,
            swiftExecutable: swiftExecutable,
            concurrencyBound: concurrencyBound
        )

        return Package.Workspace(root: root, manifests: manifests)
    }
}

extension Package.Workspace {

    private static func directoryExists(at path: Paths.Path) -> Swift.Bool {
        do throws(File.Directory.Contents.Error) {
            _ = try File.Directory(path).entries()
            return true
        } catch {
            return false
        }
    }

    private static func hasManifest(in directory: Paths.Path) -> Swift.Bool {
        File.System.Stat.isFile(at: directory / "Package.swift")
    }

    private static func findPackageDirectories(
        under root: Paths.Path,
        maxDepth: Swift.Int
    ) -> [Paths.Path] {
        var found: [Paths.Path] = []
        var queue: [(path: Paths.Path, depth: Swift.Int)] = [(root, 0)]

        while !queue.isEmpty {
            let (current, depth) = queue.removeFirst()

            if hasManifest(in: current) {
                found.append(current)
                continue
            }

            guard depth < maxDepth else { continue }

            let entries: [File.Directory.Entry]
            do throws(File.Directory.Contents.Error) {
                entries = try File.Directory(current).entries()
            } catch {
                continue
            }

            for entry in entries where entry.type == .directory {
                guard let nameString = Swift.String(entry.name),
                    !nameString.hasPrefix(".")
                else { continue }

                let component: File.Path.Component
                do throws(Paths.Path.Component.Error) {
                    component = try entry.name.asPathComponent()
                } catch {
                    continue
                }
                queue.append((current / component, depth + 1))
            }
        }
        return found
    }
}

extension Package.Workspace {

    private static func loadManifest(
        packageDirectory: Paths.Path,
        swiftExecutable: Swift.String
    ) throws(Self.Error) -> Package.Manifest {
        do throws(Package.Manager.Error) {
            return try Package.Manager(executable: swiftExecutable)
                .manifest(at: packageDirectory.string)
        } catch {
            switch error {
            case .execution:
                throw .init(kind: .subprocessError, detail: packageDirectory.string)

            case .command(let termination, let stderr):
                let message = Swift.String(decoding: stderr, as: UTF8.self)
                throw .init(
                    kind: .manifestLoadFailed,
                    detail: "'\(packageDirectory.string)' \(termination): \(message)"
                )

            case .output:
                throw .init(kind: .manifestLoadFailed, detail: packageDirectory.string)

            case .manifest:
                throw .init(kind: .invalidManifestJSON, detail: packageDirectory.string)

            case .state:

                throw .init(
                    kind: .manifestLoadFailed,
                    detail: "'\(packageDirectory.string)' unexpected resolved-state error"
                )

            case .locked:

                throw .init(
                    kind: .manifestLoadFailed,
                    detail: "'\(packageDirectory.string)' unexpected workspace-lock error"
                )

            case .timedOut:

                throw .init(
                    kind: .manifestLoadFailed,
                    detail: "'\(packageDirectory.string)' unexpected deadline error"
                )

            case .manifestUnavailable(let directory):

                throw .init(
                    kind: .manifestLoadFailed,
                    detail: "'\(directory)' manifest unavailable"
                )

            case .manifestChanged(let directory):

                throw .init(
                    kind: .manifestLoadFailed,
                    detail: "'\(directory)' manifest changed during evaluation"
                )

            case .toolchain:

                throw .init(
                    kind: .subprocessError,
                    detail: "'\(packageDirectory.string)' toolchain unavailable"
                )
            }
        }
    }

    private static func loadManifests(
        packageDirectories: [Paths.Path],
        swiftExecutable: Swift.String,
        concurrencyBound: Swift.Int
    ) async throws(Self.Error) -> [Package.Manifest] {
        var results: [Package.Manifest] = []
        var index = 0
        while index < packageDirectories.count {
            let upperIndex = Swift.min(index + concurrencyBound, packageDirectories.count)
            let chunk = Swift.Array(packageDirectories[index..<upperIndex])
            let chunkResults = try await loadChunk(chunk, swiftExecutable: swiftExecutable)
            results.append(contentsOf: chunkResults)
            index = upperIndex
        }
        return results
    }

    private static func loadChunk(
        _ chunk: [Paths.Path],
        swiftExecutable: Swift.String
    ) async throws(Self.Error) -> [Package.Manifest] {
        let exec = swiftExecutable
        do {
            return try await withThrowingTaskGroup(
                of: (Swift.Int, Package.Manifest).self
            ) { group in
                for (offset, directory) in chunk.enumerated() {
                    group.addTask {
                        let manifest = try loadManifest(
                            packageDirectory: directory,
                            swiftExecutable: exec
                        )
                        return (offset, manifest)
                    }
                }
                var indexed: [(Swift.Int, Package.Manifest)] = []
                for try await pair in group {
                    indexed.append(pair)
                }
                indexed.sort { $0.0 < $1.0 }
                return indexed.map { $0.1 }
            }
        } catch let error as Self.Error {
            throw error
        } catch is CancellationError {
            throw .init(
                kind: .subprocessError,
                detail: "concurrent manifest load cancelled"
            )
        } catch {
            throw .init(
                kind: .subprocessError,
                detail: "unexpected error during concurrent manifest load: \(error)"
            )
        }
    }
}
