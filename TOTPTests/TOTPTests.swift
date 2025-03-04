//
//  TOTPTests.swift
//  TOTPTests
//
//  Created by Lucas Fernández Aragón on 4/3/25.
//

import Testing
import Foundation
@testable import TOTP

struct TOTPTests {
    
    @Test func testHotpCodeGeneration() async throws {
        // Test case based on RFC 4226 test vectors
        let key = "12345678901234567890".data(using: .ascii)!
        
        // Test with different counters
        let expectedResults: [UInt64: UInt64] = [
            0: 755224,
            1: 287082,
            2: 359152,
            3: 969429,
            4: 338314,
            5: 254676
        ]
        
        for (counter, expected) in expectedResults {
            let result = hotpCode(key: key, digits: 6, counter: counter)
            #expect(result == expected, "HOTP code should match RFC test vector for counter \(counter)")
        }
    }
    
    @Test func testOtpEntryHotpMode() async throws {
        let key = "test-key".data(using: .utf8)!
        var entry = OtpEntry.hotp(key: key, digits: 6, counter: 0)
        
        // First code generation
        let code1 = entry.code()
        #expect(code1 > 0, "Generated HOTP code should be a positive number")
        
        // Counter should have been incremented after code generation
        if case let .hotp(_, _, counter) = entry {
            #expect(counter == 1, "Counter should be incremented after code generation")
        } else {
            #expect(1 == 0, "Entry should remain as HOTP type")
        }
        
        // Second code generation should produce a different result
        let code2 = entry.code()
        #expect(code1 != code2, "Sequential HOTP codes should be different")
    }
    
    @Test func testOtpEntryTotpMode() async throws {
        let key = "totp-test-key".data(using: .utf8)!
        var entry = OtpEntry.totp(key: key, digits: 6, interval: 30.0)
        
        // Test code generation
        let code = entry.code()
        #expect(code > 0, "Generated TOTP code should be a positive number")
        
        // Test display value is within expected range for 30-second interval
        let displayValue = entry.get_display_value()
        #expect(displayValue >= 0 && displayValue <= 30, "Display value should be between 0 and 30 seconds")
    }
    
    @Test func testOtpEntryEquality() async throws {
        let key1 = "key1".data(using: .utf8)!
        let key2 = "key2".data(using: .utf8)!
        
        let hotp1 = OtpEntry.hotp(key: key1, digits: 6, counter: 1)
        let hotp1Duplicate = OtpEntry.hotp(key: key1, digits: 6, counter: 1)
        let hotp2 = OtpEntry.hotp(key: key2, digits: 6, counter: 1)
        let hotp3 = OtpEntry.hotp(key: key1, digits: 6, counter: 2)
        
        let totp1 = OtpEntry.totp(key: key1, digits: 6, interval: 30.0)
        let totp1Duplicate = OtpEntry.totp(key: key1, digits: 6, interval: 30.0)
        let totp2 = OtpEntry.totp(key: key2, digits: 6, interval: 30.0)
        
        #expect(hotp1 == hotp1Duplicate, "Identical HOTP entries should be equal")
        #expect(hotp1 != hotp2, "HOTP entries with different keys should not be equal")
        #expect(hotp1 != hotp3, "HOTP entries with different counters should not be equal")
        
        #expect(totp1 == totp1Duplicate, "Identical TOTP entries should be equal")
        #expect(totp1 != totp2, "TOTP entries with different keys should not be equal")
        
        #expect(hotp1 != totp1, "HOTP and TOTP entries should not be equal")
    }
    
    @Test func testOtpModelConstruction() async throws {
        let key = "model-test".data(using: .utf8)!
        let entry = OtpEntry.totp(key: key, digits: 6, interval: 30.0)
        
        let model = OtpModel(issuer: "Test Issuer", name: "test@example.com", entry: entry)
        
        #expect(model.issuer == "Test Issuer", "OtpModel should store issuer correctly")
        #expect(model.name == "test@example.com", "OtpModel should store name correctly")
        
        // Test equality with identical entry
        let model2 = OtpModel(issuer: "Test Issuer", name: "test@example.com", entry: entry)
        #expect(model == model2, "OtpModels with same issuer, name and entry should be equal")
        
        // Test inequality with different properties
        let model3 = OtpModel(issuer: "Different", name: "test@example.com", entry: entry)
        #expect(model != model3, "OtpModels with different issuers should not be equal")
    }
}
