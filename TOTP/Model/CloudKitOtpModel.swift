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
    
    // CloudKit record reference
    public var record: CKRecord?
    
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
        modifiedDate: Date = Date()
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
            modifiedDate: modifiedDate
        )
        self.record = record
    }
    
    // Convert to CloudKit record
    public func toCKRecord() -> CKRecord {
        let record = self.record ?? CKRecord(recordType: CloudKitOtpModel.recordType, recordID: CKRecord.ID(recordName: id))
        
        record["issuer"] = issuer
        record["name"] = name
        record["prefix"] = prefix
        record["encryptedKey"] = encryptedKey
        record["isHotp"] = isHotp
        record["digits"] = digits
        record["interval"] = interval
        record["counter"] = counter
        record["createdDate"] = createdDate
        record["modifiedDate"] = Date() // Always update modified date when saving
        
        self.record = record
        return record
    }
    
    // Convert to local OtpModel for UI
    public func toOtpModel() throws -> OtpModel {
        let decryptedKey = try CloudKitDataManager.shared.decryptData(encryptedKey)
        
        let entry: OtpEntry
        if isHotp {
            entry = .hotp(key: decryptedKey, digits: digits, counter: UInt64(max(0, counter)))
        } else {
            entry = .totp(key: decryptedKey, digits: digits, interval: interval)
        }
        
        return OtpModel(
            issuer: issuer,
            name: name,
            prefix: prefix,
            entry: entry
        )
    }
    
    // Create from local OtpModel
    public static func from(otpModel: OtpModel) throws -> CloudKitOtpModel {
        var key: Data
        var isHotp: Bool
        var digits: Int
        var interval: Double = 30.0
        var counter: Int64 = 0
        
        switch otpModel.entry {
        case let .hotp(k, d, c):
            key = k
            isHotp = true
            digits = d
            counter = Int64(c)
        case let .totp(k, d, i):
            key = k
            isHotp = false
            digits = d
            interval = i
        }
        
        let encryptedKey = try CloudKitDataManager.shared.encryptData(key)
        
        return CloudKitOtpModel(
            issuer: otpModel.issuer,
            name: otpModel.name,
            prefix: otpModel.prefix,
            encryptedKey: encryptedKey,
            isHotp: isHotp,
            digits: digits,
            interval: interval,
            counter: counter
        )
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
