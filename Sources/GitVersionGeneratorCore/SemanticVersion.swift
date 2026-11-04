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

    /// Parses a semantic version with an optional leading `v`.
    ///
    /// Build metadata is rejected unless `allowsBuildMetadata` is true, because
    /// the generator adds its own to versions it calculates.
    init?(parsing value: String, allowsBuildMetadata: Bool = false) {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") {
            text.removeFirst()
        }

        let metadataParts = text.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        var buildMetadata: String?
        if metadataParts.count == 2 {
            guard allowsBuildMetadata, Self.isValidIdentifierList(metadataParts[1]) else { return nil }
            buildMetadata = String(metadataParts[1])
        }

        let labelParts = metadataParts[0].split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let numbers = labelParts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3,
              let major = Self.parseNumber(numbers[0]),
              let minor = Self.parseNumber(numbers[1]),
              let patch = Self.parseNumber(numbers[2]) else {
            return nil
        }

        var label: String?
        if labelParts.count == 2 {
            guard Self.isValidIdentifierList(labelParts[1]),
                  !labelParts[1].split(separator: ".").contains(where: Self.hasLeadingZero) else {
                return nil
            }
            label = String(labelParts[1])
        }

        self.init(major: major, minor: minor, patch: patch, label: label, buildMetadata: buildMetadata)
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
