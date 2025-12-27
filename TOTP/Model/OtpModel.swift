import Foundation

public struct OtpModel: Identifiable, Hashable {
    public static func == (lhs: OtpModel, rhs: OtpModel) -> Bool {
        lhs.id == rhs.id || (lhs.issuer == rhs.issuer && lhs.name == rhs.name && lhs.entry == rhs.entry && lhs.prefix == rhs.prefix)
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(issuer)
        hasher.combine(name)
        hasher.combine(prefix)
        hasher.combine(entry)
    }
    
    public let id: UUID
    public var issuer: String?
    public var name: String?
    public var prefix: String?
    public var entry: OtpEntry
    
    /// Associated domains for AutoFill matching (e.g., ["github.com", "www.github.com"])
    public var associatedDomains: [String]?
    
    /// Record identifier for ASCredentialIdentityStore
    public var recordIdentifier: String {
        id.uuidString
    }
    
    public init(id: UUID = UUID(), issuer: String? = nil, name: String? = nil, prefix: String? = nil, entry: OtpEntry, associatedDomains: [String]? = nil) {
        self.id = id
        self.issuer = issuer
        self.name = name
        self.prefix = prefix
        self.entry = entry
        self.associatedDomains = associatedDomains
    }
    
    /// Generates the current TOTP/HOTP code as a string
    public func generateCode() -> String {
        var entryCopy = entry
        let code = entryCopy.code()
        let digits: Int
        switch entry {
        case .hotp(_, let d, _), .totp(_, let d, _):
            digits = d
        }
        return String(format: "%0\(digits)d", Int(code))
    }
    
    /// Generates the autofill value (prefix + code if prefix exists, otherwise just code)
    public func generateAutoFillValue() -> String {
        let code = generateCode()
        if let prefix = prefix, !prefix.isEmpty {
            return prefix + code
        }
        return code
    }
}
