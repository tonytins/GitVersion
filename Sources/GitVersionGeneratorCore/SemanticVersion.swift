import Foundation

struct SemanticVersion: Equatable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    let label: String?
    let buildMetadata: String?

    var description: String {
        var value = "\(major).\(minor).\(patch)"
        if let label {
            value += "-\(label)"
        }
        if let buildMetadata {
            value += "+\(buildMetadata)"
        }
        return value
    }

    init(major: Int, minor: Int, patch: Int, label: String? = nil, buildMetadata: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.label = label
        self.buildMetadata = buildMetadata
    }

    /// Parses a semantic version using the same forms as a GitInfo base version.
    ///
    /// Accepted:
    ///
    /// - `1.2.3` or `1.2` (patch defaults to zero), with an optional leading
    ///   `v` or `V`.
    /// - A trailing prerelease label, such as `1.2.3-preview.1` or `1.2-beta`.
    /// - A leading label, such as `preview-1.2.3`, which becomes `1.2.3-preview`.
    ///
    /// Build metadata is rejected unless `allowsBuildMetadata` is true, because
    /// the generator adds its own to the versions it calculates.
    init?(parsing value: String, allowsBuildMetadata: Bool = false) {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)

        var core = text
        var buildMetadata: String?
        if let plus = text.firstIndex(of: "+") {
            let metadata = text[text.index(after: plus)...]
            guard allowsBuildMetadata, Self.isValidIdentifierList(metadata) else { return nil }
            buildMetadata = String(metadata)
            core = String(text[..<plus])
        }

        guard let components = Self.parseCore(core) else { return nil }
        self.init(
            major: components.major,
            minor: components.minor,
            patch: components.patch,
            label: components.label,
            buildMetadata: buildMetadata
        )
    }

    /// Whether this version sorts before `other` under semantic version precedence.
    func hasLowerPrecedence(than other: SemanticVersion) -> Bool {
        let numbers = [major, minor, patch]
        let otherNumbers = [other.major, other.minor, other.patch]
        if numbers != otherNumbers {
            return numbers.lexicographicallyPrecedes(otherNumbers)
        }

        switch (label, other.label) {
        case (nil, _):
            return false
        case (_?, nil):
            return true
        case let (label?, otherLabel?):
            return Self.labelPrecedes(label, otherLabel)
        }
    }

    private struct Components {
        let major: Int
        let minor: Int
        let patch: Int
        let label: String?
    }

    /// Parses a version without build metadata.
    ///
    /// The standard form is tried before the leading-label form so that
    /// `1.2-3.4.5` reads as `1.2.0` with the label `3.4.5`, not as `3.4.5`
    /// with the label `1.2`. The leading `v` is only stripped for the standard
    /// form, because it may belong to the label (`version-1.2.3`).
    private static func parseCore(_ text: String) -> Components? {
        let unprefixed = text.hasPrefix("v") || text.hasPrefix("V") ? text.dropFirst() : Substring(text)
        return parseNumbers(unprefixed) ?? parseLabelPrefixed(text)
    }

    /// Parses `M.m[.p][-label]`. The label may contain dashes.
    private static func parseNumbers(_ text: Substring) -> Components? {
        let labelStart = text.firstIndex(of: "-")
        let numbers = labelStart.map { text[..<$0] } ?? text
        let label = labelStart.map { text[text.index(after: $0)...] }

        let components = numbers.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 2 || components.count == 3,
              let major = parseNumber(components[0]),
              let minor = parseNumber(components[1]) else {
            return nil
        }
        let patch = components.count == 3 ? parseNumber(components[2]) : 0
        guard let patch else { return nil }

        var parsedLabel: String?
        if let label {
            guard isValidIdentifierList(label),
                  !label.split(separator: ".").contains(where: hasLeadingZero) else {
                return nil
            }
            parsedLabel = String(label)
        }
        return Components(major: major, minor: minor, patch: patch, label: parsedLabel)
    }

    /// Parses `label-M.m.p`. The label may contain dashes, so each dash is
    /// tried from the right until one is followed by a complete version. The
    /// version after the dash may carry a leading `v`.
    private static func parseLabelPrefixed(_ text: String) -> Components? {
        var searchEnd = text.endIndex
        while let dash = text[..<searchEnd].lastIndex(of: "-") {
            let label = text[..<dash]
            var version = text[text.index(after: dash)...]
            if version.hasPrefix("v") || version.hasPrefix("V") {
                version = version.dropFirst()
            }
            let components = version.split(separator: ".", omittingEmptySubsequences: false)
            if components.count == 3,
               let major = parseNumber(components[0]),
               let minor = parseNumber(components[1]),
               let patch = parseNumber(components[2]),
               isValidIdentifierList(label),
               !label.split(separator: ".").contains(where: hasLeadingZero) {
                return Components(major: major, minor: minor, patch: patch, label: String(label))
            }
            searchEnd = dash
        }
        return nil
    }

    private static func parseNumber(_ value: Substring) -> Int? {
        guard !value.isEmpty,
              value.allSatisfy({ $0.isASCII && $0.isNumber }),
              value.count == 1 || !value.hasPrefix("0") else {
            return nil
        }
        return Int(value)
    }

    private static func isValidIdentifierList(_ value: Substring) -> Bool {
        value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { identifier in
            !identifier.isEmpty && identifier.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    private static func hasLeadingZero(_ identifier: Substring) -> Bool {
        identifier.count > 1 && identifier.hasPrefix("0") && identifier.allSatisfy(\.isNumber)
    }

    private static func labelPrecedes(_ label: String, _ otherLabel: String) -> Bool {
        let identifiers = label.split(separator: ".")
        let otherIdentifiers = otherLabel.split(separator: ".")
        for (identifier, otherIdentifier) in zip(identifiers, otherIdentifiers) where identifier != otherIdentifier {
            switch (Int(identifier), Int(otherIdentifier)) {
            case let (number?, otherNumber?):
                return number < otherNumber
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return identifier < otherIdentifier
            }
        }
        return identifiers.count < otherIdentifiers.count
    }
}
