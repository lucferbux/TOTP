//
//  CloudKitOtpModel.swift
//  TOTP
//
//  CloudKit-compatible OTP model for iCloud synchronization
//

import Foundation
import CloudKit
import CryptoKit

// CloudKit record for storing OTP accounts
public class CloudKitOtpModel: ObservableObject {
    static let recordType = "TOTPAccount"
    
    public let id: String
    @Published public var issuer: String?
    @Published public var name: String?
    @Published public var prefix: String?
    @Published public var encryptedKey: Data
    @Published public var isHotp: Bool
    @Published public var digits: Int
    @Published public var interval: Double
    @Published public var counter: Int64
    @Published public var createdDate: Date
    @Published public var modifiedDate: Date
    @Published public var associatedDomains: [String]?
    /// Hash algorithm raw value; `nil` means SHA-1. Only written for non-SHA-1 accounts so
    /// existing records (and the production schema) stay untouched.
    @Published public var algorithm: String?
    
    // CloudKit record reference
    public var record: CKRecord?

    /// The prefix (PIN), sealed with the account key. From 4.4 on this replaces the plaintext
    /// `prefix` field, which is still read so records written by ≤4.3 keep working.
    @Published public var encryptedPrefix: Data?

    /// False when the record was sealed with a legacy key, or still carries a plaintext prefix,
    /// and should be re-uploaded.
    public private(set) var sealedWithPrimaryKey = true
    
    public init(
        id: String = UUID().uuidString,
        issuer: String? = nil,
        name: String? = nil,
        prefix: String? = nil,
        encryptedKey: Data,
        isHotp: Bool = false,
        digits: Int = 6,
        interval: Double = 30.0,
        counter: Int64 = 0,
        createdDate: Date = Date(),
        modifiedDate: Date = Date(),
        associatedDomains: [String]? = nil,
        algorithm: String? = nil,
        encryptedPrefix: Data? = nil
    ) {
        self.id = id
        self.issuer = issuer
        self.name = name
        self.prefix = prefix
        self.encryptedKey = encryptedKey
        self.isHotp = isHotp
        self.digits = digits
        self.interval = interval
        self.counter = counter
        self.createdDate = createdDate
        self.modifiedDate = modifiedDate
        self.associatedDomains = associatedDomains
        self.algorithm = algorithm
        self.encryptedPrefix = encryptedPrefix
    }
    
    // Initialize from CloudKit record
    public convenience init?(from record: CKRecord) {
        guard let encryptedKey = record["encryptedKey"] as? Data,
              let isHotp = record["isHotp"] as? Bool,
              let digits = record["digits"] as? Int,
              let interval = record["interval"] as? Double,
              let counter = record["counter"] as? Int64,
              let createdDate = record["createdDate"] as? Date,
              let modifiedDate = record["modifiedDate"] as? Date else {
            return nil
        }
        
        self.init(
            id: record.recordID.recordName,
            issuer: record["issuer"] as? String,
            name: record["name"] as? String,
            prefix: record["prefix"] as? String,
            encryptedKey: encryptedKey,
            isHotp: isHotp,
            digits: digits,
            interval: interval,
            counter: counter,
            createdDate: createdDate,
            modifiedDate: modifiedDate,
            associatedDomains: record["associatedDomains"] as? [String],
            algorithm: record["algorithm"] as? String,
            encryptedPrefix: record["encryptedPrefix"] as? Data
        )
        self.record = record
    }
    
    // Convert to CloudKit record
    public func toCKRecord(in zoneID: CKRecordZone.ID? = nil) -> CKRecord {
        let recordID = zoneID.map { CKRecord.ID(recordName: id, zoneID: $0) } ?? CKRecord.ID(recordName: id)
        let record = self.record ?? CKRecord(recordType: CloudKitOtpModel.recordType, recordID: recordID)
        
        record["issuer"] = issuer
        record["name"] = name
        // The PIN is sealed; never upload it in the clear (a ≤4.3 record may still have one,
        // which we clear as soon as we rewrite the record).
        record["prefix"] = nil
        record["encryptedPrefix"] = encryptedPrefix
        record["encryptedKey"] = encryptedKey
        record["isHotp"] = isHotp
        record["digits"] = digits
        record["interval"] = interval
        record["counter"] = counter
        record["createdDate"] = createdDate
        record["modifiedDate"] = Date() // Always update modified date when saving
        record["associatedDomains"] = associatedDomains
        if let algorithm {
            record["algorithm"] = algorithm
        } else if record["algorithm"] != nil {
            record["algorithm"] = nil
        }
        
        self.record = record
        return record
    }
    
    // Convert to local OtpModel for UI
    public func toOtpModel() throws -> OtpModel {
        let manager = EncryptionKeyManager.shared
        let decryptedKey = try manager.decryptData(encryptedKey)
        let resolvedPrefix: String?
        if let encryptedPrefix {
            resolvedPrefix = String(data: try manager.decryptData(encryptedPrefix), encoding: .utf8)
        } else {
            resolvedPrefix = prefix   // written by ≤4.3
        }
        // Records sealed with an older key — or still carrying a plaintext prefix — get re-uploaded
        // by SyncManager after they load.
        if let primary = manager.primaryKey {
            sealedWithPrimaryKey = (try? AccountCrypto.open(encryptedKey, using: primary)) != nil && prefix == nil
        } else {
            sealedWithPrimaryKey = true   // can't tell without a key; don't churn uploads
        }
        
        let algorithm = algorithm.flatMap(OtpAlgorithm.init(lenient:)) ?? .sha1
        let entry: OtpEntry = isHotp
            ? .hotp(key: decryptedKey, digits: digits, counter: UInt64(max(0, counter)), algorithm: algorithm)
            : .totp(key: decryptedKey, digits: digits, interval: interval, algorithm: algorithm)
        
        return OtpModel(
            id: UUID(uuidString: id) ?? UUID(),
            issuer: issuer,
            name: name,
            prefix: resolvedPrefix,
            entry: entry,
            associatedDomains: associatedDomains
        )
    }
    
    // Create from local OtpModel
    public static func from(otpModel: OtpModel) throws -> CloudKitOtpModel {
        let model = CloudKitOtpModel(
            id: otpModel.id.uuidString,
            encryptedKey: Data()
        )
        try model.apply(otpModel)
        return model
    }
    
    /// Copies every field of `otpModel` (encrypting the secret) onto this record model.
    public func apply(_ otpModel: OtpModel) throws {
        let entry = otpModel.entry
        issuer = otpModel.issuer
        name = otpModel.name
        prefix = nil
        associatedDomains = otpModel.associatedDomains
        encryptedKey = try EncryptionKeyManager.shared.encryptData(entry.key)
        encryptedPrefix = try otpModel.prefix.flatMap { value -> Data? in
            value.isEmpty ? nil : try EncryptionKeyManager.shared.encryptData(Data(value.utf8))
        }
        isHotp = entry.isHotp
        digits = entry.digits
        interval = entry.interval ?? 30
        counter = Int64(clamping: entry.counter ?? 0)
        algorithm = entry.algorithm == .sha1 ? nil : entry.algorithm.rawValue
    }
}

extension CloudKitOtpModel: Identifiable {}

extension CloudKitOtpModel: Hashable {
    public static func == (lhs: CloudKitOtpModel, rhs: CloudKitOtpModel) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
