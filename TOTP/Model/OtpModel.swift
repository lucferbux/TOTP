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
    
    public init(id: UUID = UUID(), issuer: String? = nil, name: String? = nil, prefix: String? = nil, entry: OtpEntry) {
        self.id = id
        self.issuer = issuer
        self.name = name
        self.prefix = prefix
        self.entry = entry
    }
}
