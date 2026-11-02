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
