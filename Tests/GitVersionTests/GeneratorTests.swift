import Foundation
import Testing
@testable import GitVersionGeneratorCore

// MARK: - Fixtures

private let baseEnvironment: [String: String] = [
    "PATH": ProcessInfo.processInfo.environment["PATH", default: ""],
    "GIT_CONFIG_GLOBAL": "/dev/null",
    "GIT_CONFIG_NOSYSTEM": "1"
]

/// A throwaway Git repository that is removed when the fixture is released.
private final class TemporaryRepository {
    let root: URL
    private let git: GitCommand

    init(initialize: Bool = true) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitVersionTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        git = try GitCommand(environment: baseEnvironment)
        if initialize {
            try run("init", "-q", "-b", "main")
            try run("config", "user.name", "Test")
            try run("config", "user.email", "test@example.invalid")
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func run(_ arguments: String...) throws -> String {
        try git.output(arguments, in: root)
    }

    func commit(_ message: String = "commit") throws {
        try run("commit", "-q", "--allow-empty", "-m", message)
    }

    func commitFile(_ path: String, contents: String = "x\n", message: String = "change") throws {
        try write(path, contents: contents)
        try run("add", "--", path)
        try commit(message)
    }

    func write(_ path: String, contents: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func info(
        package: String? = nil,
        environment: [String: String] = [:]
    ) throws -> RepositoryInfo {
        let directory = package.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
        return try collectInfo(
            package: directory,
            environment: baseEnvironment.merging(environment) { _, new in new }
        )
    }
}

private func coreVersion(_ info: RepositoryInfo) -> String {
    let version = info.semanticVersion
    return "\(version.major).\(version.minor).\(version.patch)" + (version.label.map { "-\($0)" } ?? "")
}

// MARK: - Version parsing

@Test(arguments: ["1.2.3", "v1.2.3", "0.0.0", "1.2.3-preview.1", "1.2.3-rc-1", "1.2.3-0a", " 1.2.3\n"])
func acceptsValidVersions(_ value: String) {
    #expect(SemanticVersion(parsing: value) != nil)
}

@Test(arguments: [
    "", "1", "1.2", "1.2.3.4", "01.2.3", "1.2.3-", "1.2.3-a..b", "1.2.3-.a", "1.2.3-a.", "1.2.3-01",
    "1.2.3-é", "1.2.3+x", "x.y.z", "v2-beta"
])
func rejectsInvalidVersions(_ value: String) {
    #expect(SemanticVersion(parsing: value) == nil)
}

@Test func buildMetadataIsOnlyAcceptedWhenAllowed() {
    #expect(SemanticVersion(parsing: "1.2.3+x.y", allowsBuildMetadata: true)?.buildMetadata == "x.y")
    #expect(SemanticVersion(parsing: "1.2.3+", allowsBuildMetadata: true) == nil)
    #expect(SemanticVersion(parsing: "1.2.3+a..b", allowsBuildMetadata: true) == nil)
}

@Test(arguments: [
    ("1.0.0", "2.0.0"), ("1.0.0", "1.1.0"), ("1.0.0", "1.0.1"), ("1.0.0-rc.1", "1.0.0"),
    ("1.0.0-alpha", "1.0.0-alpha.1"), ("1.0.0-alpha.1", "1.0.0-alpha.beta"),
    ("1.0.0-rc.2", "1.0.0-rc.10"), ("1.0.0-beta", "1.0.0-rc")
])
func comparesPrecedence(_ lower: String, _ higher: String) throws {
    let lowerVersion = try #require(SemanticVersion(parsing: lower))
    let higherVersion = try #require(SemanticVersion(parsing: higher))
    #expect(lowerVersion.hasLowerPrecedence(than: higherVersion))
    #expect(!higherVersion.hasLowerPrecedence(than: lowerVersion))
}

// MARK: - Remote URLs and branch names

@Test(arguments: [
    ("https://github.com/a/b.git", "https://github.com/a/b.git"),
    ("https://alice:secret@github.com/a/b.git", "https://github.com/a/b.git"),
    ("https://token@github.com/a/b.git", "https://github.com/a/b.git"),
    ("ssh://git@github.com/a/b.git", "ssh://github.com/a/b.git"),
    ("git@github.com:a/b.git", "git@github.com:a/b.git"),
    ("https://github.com/user@example/b.git", "https://github.com/user@example/b.git")
] as [(String, String)])
func keepsPublicRemotesWithoutCredentials(_ remote: String, _ expected: String) {
    #expect(publicRemoteURL(remote) == expected)
}

@Test(arguments: ["/srv/repo.git", "./repo", "../repo", "repo.git", "C:\\repo", "C:/repo", "file:///srv/repo.git"])
func hidesLocalRemotes(_ remote: String) {
    #expect(publicRemoteURL(remote) == nil)
}

@Test(arguments: [
    ("main", "main"), ("feature/Foo_Bar", "feature.foo.bar"), ("a--b", "a--b"), ("/x/", "x")
] as [(String, String)])
func normalizesBranchNames(_ branch: String, _ expected: String) {
    #expect(normalizedIdentifier(branch) == expected)
}

@Test func branchWithNoUsableCharactersHasNoIdentifier() {
    #expect(normalizedIdentifier("日本語") == nil)
}

@Test(arguments: [
    (["GITHUB_SHA": "abc", "GITHUB_HEAD_REF": "pr-branch", "GITHUB_REF_NAME": "42/merge"], "pr-branch"),
    (["GITHUB_SHA": "abc", "GITHUB_REF_TYPE": "branch", "GITHUB_REF_NAME": "main"], "main"),
    (["GITHUB_SHA": "abc", "GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "v1.0.0"], nil),
    (["GITHUB_SHA": "other", "GITHUB_HEAD_REF": "host-pr"], nil),
    (["CI_COMMIT_SHA": "abc", "CI_COMMIT_REF_NAME": "main"], "main"),
    (["CI_COMMIT_SHA": "abc", "CI_COMMIT_REF_NAME": "v1.0.0", "CI_COMMIT_TAG": "v1.0.0"], nil),
    (["BUILD_SOURCEVERSION": "abc", "BUILD_SOURCEBRANCH": "refs/heads/feature/x"], "feature/x"),
    (["BUILD_SOURCEVERSION": "abc", "BUILD_SOURCEBRANCH": "refs/tags/v1.0.0"], nil),
    (["GIT_COMMIT": "abc", "GIT_BRANCH": "origin/main"], "main"),
    ([:], nil)
] as [([String: String], String?)])
func readsContinuousIntegrationBranch(_ environment: [String: String], _ expected: String?) {
    #expect(continuousIntegrationBranch(in: environment, commit: "abc") == expected)
}

// MARK: - Closest reset

@Test func startsAtDefaultVersionWithNoResets() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    try repository.commit()
    try repository.commit()
    #expect(coreVersion(try repository.info()) == "0.1.2")
}

@Test func incrementsFromVersionFile() throws {
    let repository = try TemporaryRepository()
    try repository.commitFile("GitVersion.txt", contents: "1.2.3-preview.1\n")
    try repository.commit()
    let info = try repository.info()
    #expect(coreVersion(info) == "1.2.4-preview.1")
    #expect(info.commits == 1)
}

@Test func tagOnHeadBeatsOlderVersionFile() throws {
    let repository = try TemporaryRepository()
    try repository.commitFile("GitVersion.txt", contents: "0.1.0\n")
    try repository.commit()
    try repository.run("tag", "v5.0.0")
    let info = try repository.info()
    #expect(coreVersion(info) == "5.0.0")
    #expect(info.tag == "v5.0.0")
}

@Test func versionDoesNotFallBackAfterTag() throws {
    let repository = try TemporaryRepository()
    try repository.commitFile("GitVersion.txt", contents: "0.1.0\n")
    try repository.commit()
    try repository.run("tag", "v5.0.0")
    try repository.commit()
    let info = try repository.info()
    #expect(coreVersion(info) == "5.0.1")
    #expect(info.tag == nil)
    #expect(info.baseTag == "v5.0.0")
}

@Test func versionFileChangeBeatsOlderTag() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    try repository.run("tag", "v5.0.0")
    try repository.commitFile("GitVersion.txt", contents: "6.0.0\n")
    try repository.commit()
    #expect(coreVersion(try repository.info()) == "6.0.1")
}

@Test func tagWinsOverVersionFileOnSameCommit() throws {
    let repository = try TemporaryRepository()
    try repository.commitFile("GitVersion.txt", contents: "1.0.0\n")
    try repository.run("tag", "v2.0.0")
    #expect(coreVersion(try repository.info()) == "2.0.0")
}

@Test func annotatedTagsAreResets() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    try repository.run("tag", "-a", "v3.0.0", "-m", "release")
    try repository.commit()
    #expect(coreVersion(try repository.info()) == "3.0.1")
}

@Test func releaseTagBeatsPrereleaseTagOnSameCommit() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    try repository.run("tag", "v1.0.0-rc.1")
    try repository.run("tag", "v1.0.0")
    #expect(coreVersion(try repository.info()) == "1.0.0")
}

@Test(arguments: ["v2-beta", "release", "v1.2"])
func skipsUnparseableTags(_ tag: String) throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    try repository.run("tag", "v1.0.0")
    try repository.commit()
    try repository.run("tag", tag)
    try repository.commit()
    let info = try repository.info()
    #expect(coreVersion(info) == "1.0.2")
    #expect(info.baseTag == "v1.0.0")
}

@Test func tagWithBuildMetadataIsAReset() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    try repository.run("tag", "v1.2.3+x")
    try repository.commit()
    #expect(coreVersion(try repository.info()) == "1.2.4")
}

@Test func unrelatedTagOnHeadIsStillReported() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    try repository.run("tag", "nightly")
    let info = try repository.info()
    #expect(info.tag == "nightly")
    #expect(info.baseTag == nil)
}

@Test func tagOnlyReachableThroughMergeIsNotAReset() throws {
    let repository = try TemporaryRepository()
    try repository.commitFile("GitVersion.txt", contents: "1.0.0\n")
    try repository.run("checkout", "-q", "-b", "side")
    try repository.commit()
    try repository.run("tag", "v9.0.0")
    try repository.run("checkout", "-q", "main")
    try repository.run("merge", "-q", "--no-ff", "-m", "merge", "side")
    #expect(coreVersion(try repository.info()) == "1.0.1")
}

// MARK: - First-parent counting

@Test func countsMergeButNotSideCommits() throws {
    let repository = try TemporaryRepository()
    try repository.commitFile("GitVersion.txt", contents: "1.0.0\n")
    try repository.run("checkout", "-q", "-b", "side")
    try repository.commit()
    try repository.commit()
    try repository.commit()
    try repository.run("checkout", "-q", "main")
    try repository.run("merge", "-q", "--no-ff", "-m", "merge", "side")
    #expect(coreVersion(try repository.info()) == "1.0.1")
}

@Test func versionFileChangedOnSideBranchResetsAtMerge() throws {
    let repository = try TemporaryRepository()
    try repository.commitFile("GitVersion.txt", contents: "1.0.0\n")
    try repository.run("checkout", "-q", "-b", "side")
    try repository.commitFile("GitVersion.txt", contents: "2.0.0\n")
    try repository.commit()
    try repository.run("checkout", "-q", "main")
    try repository.commit()
    try repository.run("merge", "-q", "--no-ff", "-m", "merge", "side")
    try repository.commit()
    #expect(coreVersion(try repository.info()) == "2.0.1")
}

@Test func uncommittedVersionFileTakesEffectAtHead() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    try repository.commit()
    try repository.write("GitVersion.txt", contents: "3.0.0\n")
    let info = try repository.info()
    #expect(coreVersion(info) == "3.0.0")
    #expect(info.isDirty)
}

// MARK: - Nested packages

@Test func findsNestedVersionFileAndCountsItsDirectory() throws {
    let repository = try TemporaryRepository()
    try repository.commitFile("packages/app/GitVersion.txt", contents: "9.0.0\n")
    try repository.commit()
    try repository.commitFile("packages/other/file.txt")
    try repository.commitFile("packages/app/Sources/file.txt")
    #expect(coreVersion(try repository.info(package: "packages/app")) == "9.0.1")
}

@Test func searchesUpwardForVersionFile() throws {
    let repository = try TemporaryRepository()
    try repository.commitFile("packages/GitVersion.txt", contents: "4.0.0\n")
    try repository.commitFile("packages/app/file.txt")
    try repository.commitFile("elsewhere/file.txt")
    #expect(coreVersion(try repository.info(package: "packages/app")) == "4.0.1")
}

@Test func closestVersionFileToPackageWins() throws {
    let repository = try TemporaryRepository()
    try repository.commitFile("GitVersion.txt", contents: "1.0.0\n")
    try repository.commitFile("app/GitVersion.txt", contents: "2.0.0\n")
    #expect(coreVersion(try repository.info(package: "app")) == "2.0.0")
}

@Test func packagesBesideVersionFileDirectoryDoNotUseIt() throws {
    let repository = try TemporaryRepository()
    try repository.commitFile("app/GitVersion.txt", contents: "2.0.0\n")
    try repository.commitFile("other/file.txt")
    #expect(coreVersion(try repository.info(package: "other")) == "0.1.1")
}

// MARK: - Repository state

@Test func reportsDirtyStateInBuildMetadata() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    #expect(try repository.info().semanticVersion.buildMetadata?.hasSuffix(".dirty") == false)
    try repository.write("untracked.txt", contents: "x\n")
    #expect(try repository.info().semanticVersion.buildMetadata?.hasSuffix(".dirty") == true)
}

@Test func untrackedFilesAreDirtyWhateverTheStatusConfiguration() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    try repository.run("config", "status.showUntrackedFiles", "no")
    try repository.write("untracked.txt", contents: "x\n")
    #expect(try repository.info().isDirty)
}

@Test func detachedCheckoutHasNoBranchAndOneCommitIdentifier() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    try repository.run("checkout", "-q", "--detach")
    let info = try repository.info()
    #expect(info.branch == nil)
    #expect(info.semanticVersion.buildMetadata == info.commit)
    #expect(info.fullCommit?.count == 40)
    #expect(info.fullCommit?.hasPrefix(try #require(info.commit)) == true)
}

@Test func detachedCheckoutUsesMatchingContinuousIntegrationBranch() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    try repository.run("checkout", "-q", "--detach")
    let head = try repository.run("rev-parse", "HEAD")
    let matching = try repository.info(environment: ["GIT_COMMIT": head, "GIT_BRANCH": "origin/main"])
    #expect(matching.branch == "main")
    let other = try repository.info(environment: ["GIT_COMMIT": "0000", "GIT_BRANCH": "origin/main"])
    #expect(other.branch == nil)
}

@Test func branchAndTagWithSameNameDoNotBreakCollection() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    try repository.run("tag", "v1.0.0")
    try repository.commit()
    try repository.run("branch", "v1.0.0")
    try repository.commit()
    #expect(coreVersion(try repository.info()) == "1.0.2")
}

@Test func gitTraceDoesNotAffectMetadata() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    let info = try repository.info(environment: ["GIT_TRACE": "1"])
    #expect(info.commit?.count == 12)
    #expect(!info.isDirty)
}

@Test func repositoryVariablesFromGitHooksAreIgnored() throws {
    let repository = try TemporaryRepository()
    let other = try TemporaryRepository()
    try repository.commit("this repository")
    try other.commit("another repository")
    let expected = try repository.run("rev-parse", "HEAD")
    let info = try repository.info(environment: ["GIT_DIR": other.root.appendingPathComponent(".git").path])
    #expect(info.fullCommit == expected)
}

@Test func removesCredentialsFromRepositoryURL() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    try repository.run("remote", "add", "origin", "https://alice:secret@github.com/a/b.git")
    #expect(try repository.info().repositoryURL == "https://github.com/a/b.git")
}

// MARK: - Failures

@Test func shallowCloneFails() throws {
    let source = try TemporaryRepository()
    try source.commit()
    try source.commit()
    let clone = try TemporaryRepository(initialize: false)
    try clone.run("clone", "-q", "--depth", "1", "file://\(source.root.path)", ".")
    #expect(throws: GeneratorError.self) { try clone.info() }
}

@Test func repositoryWithNoCommitsFails() throws {
    let repository = try TemporaryRepository()
    #expect(throws: GeneratorError.self) { try repository.info() }
}

@Test func corruptRepositoryFailsInsteadOfReportingUnknown() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    try FileManager.default.removeItem(at: repository.root.appendingPathComponent(".git/HEAD"))
    #expect(throws: GeneratorError.self) { try repository.info() }
}

@Test(arguments: ["", "not a version\n", "1.2.3-\n"])
func invalidVersionFileFails(_ contents: String) throws {
    let repository = try TemporaryRepository()
    try repository.commitFile("GitVersion.txt", contents: contents)
    #expect(throws: GeneratorError.self) { try repository.info() }
}

// MARK: - Builds without a repository

@Test func noRepositoryReportsUnknownWithWarning() throws {
    let directory = try TemporaryRepository(initialize: false)
    let info = try directory.info()
    #expect(info.semanticVersion.description == "0.0.0+unknown")
    #expect(info.commit == nil)
    #expect(info.branch == nil)
    #expect(info.warning != nil)
}

@Test func noRepositoryUsesVersionFileAsUnknownBaseline() throws {
    let directory = try TemporaryRepository(initialize: false)
    try directory.write("GitVersion.txt", contents: "1.2.0\n")
    #expect(try directory.info().semanticVersion.description == "1.2.0+unknown")
}

@Test func noRepositoryDoesNotNeedGit() throws {
    let directory = try TemporaryRepository(initialize: false)
    let info = try collectInfo(package: directory.root, environment: ["PATH": ""])
    #expect(info.semanticVersion.description == "0.0.0+unknown")
}

@Test func repositoryWithoutGitInstalledFails() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    #expect(throws: GeneratorError.self) {
        try collectInfo(package: repository.root, environment: ["PATH": ""])
    }
}

@Test func overrideReplacesEverything() throws {
    let repository = try TemporaryRepository()
    try repository.commitFile("GitVersion.txt", contents: "1.0.0\n")
    let info = try repository.info(environment: ["GITVERSION_VERSION": "1.2.7+fedora.1"])
    #expect(info.semanticVersion.description == "1.2.7+fedora.1")
    #expect(info.baseVersion.description == "1.2.7")
    #expect(info.commit == nil)
    #expect(info.warning == nil)
}

@Test func overrideWorksInShallowClone() throws {
    let source = try TemporaryRepository()
    try source.commit()
    try source.commit()
    let clone = try TemporaryRepository(initialize: false)
    try clone.run("clone", "-q", "--depth", "1", "file://\(source.root.path)", ".")
    #expect(try clone.info(environment: ["GITVERSION_VERSION": "1.2.7"]).semanticVersion.description == "1.2.7")
}

@Test func invalidOverrideFails() throws {
    let directory = try TemporaryRepository(initialize: false)
    #expect(throws: GeneratorError.self) {
        try directory.info(environment: ["GITVERSION_VERSION": "banana"])
    }
}

@Test func emptyOverrideIsIgnored() throws {
    let directory = try TemporaryRepository(initialize: false)
    #expect(try directory.info(environment: ["GITVERSION_VERSION": ""]).semanticVersion.description == "0.0.0+unknown")
}

// MARK: - Generated source

@Test func generatedSourceEscapesValuesAndHasNoPublicAPI() throws {
    let repository = try TemporaryRepository()
    try repository.commit()
    try repository.run("checkout", "-q", "-b", #"we"ird$(x)"#)
    try repository.run("remote", "add", "origin", #"https://x/"); fatalError("pwn"#)
    let source = generatedSource(for: try repository.info())
    #expect(source.contains(#"Optional("we\"ird$(x)")"#))
    #expect(source.contains(#"Optional("https://x/\"); fatalError(\"pwn")"#))
    #expect(!source.contains("public"))
}
