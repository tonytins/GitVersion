import GitVersion
import Testing

@Test func formatsSemanticVersions() {
    let version = GitSemanticVersion(
        major: 2,
        minor: 4,
        patch: 1,
        label: "preview.3",
        buildMetadata: "main.abc123"
    )

    #expect(version.description == "2.4.1-preview.3+main.abc123")
}

@Test func formatsStableSemanticVersions() {
    let version = GitSemanticVersion(major: 1, minor: 0, patch: 0)

    #expect(version.description == "1.0.0")
}

@Test func exposesVersionComponentsAndFullCommit() {
    let version = GitSemanticVersion(major: 3, minor: 2, patch: 1)
    let info = GitVersionInfo(
        repositoryURL: nil,
        branch: "main",
        commit: "a1b2c3d4e5f6",
        fullCommit: "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678",
        commitDate: "2026-11-02T00:00:00Z",
        commits: 0,
        tag: "v3.2.1",
        baseTag: "v3.2.1",
        isDirty: false,
        baseVersion: version,
        semanticVersion: version
    )

    #expect(info.major == 3)
    #expect(info.minor == 2)
    #expect(info.patch == 1)
    #expect(info.commit == "a1b2c3d4e5f6")
    #expect(info.fullCommit == "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678")
}

@Test func generatedPatchIncludesFirstParentCommitCount() {
    let version = GitVersion.current

    #expect(version.patch == version.baseVersion.patch + version.commits)
}
