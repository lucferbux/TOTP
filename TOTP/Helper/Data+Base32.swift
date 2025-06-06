import Foundation

// Extension to provide Base32 decoding functionality
extension Data {
    init?(base32Encoded base32String: String) {
        let string = base32String.uppercased().replacingOccurrences(of: "=", with: "")
        guard !string.isEmpty, string.count % 8 == 0 || string.count % 8 == 2 || string.count % 8 == 4 || string.count % 8 == 5 || string.count % 8 == 7 else {
            // Invalid length for Base32 string (must be multiple of 8, or padded)
            // Or, more precisely, the unpadded length must be one of 2, 4, 5, 7, or a multiple of 8.
            // For simplicity here, we'll rely on the character check and nil return for invalid chars.
            // A more robust check would validate padding, but OTP secrets usually aren't padded in user input.
            // print("Invalid Base32 string length or padding")
            return nil
        }

        var S = [UInt8]()
        for C in string.unicodeScalars {
            var cval: UInt8 = 0
            switch C {
                case "A"..."Z": cval = UInt8(C.value - UnicodeScalar("A").value)
                case "2"..."7": cval = UInt8(C.value - UnicodeScalar("2").value) + 26
                default:
                    // print("Invalid character in Base32 string: \(C)")
                    return nil // Invalid character
            }
            S.append(cval)
        }

        var data = Data()
        var D: UInt64 = 0
        var i = 0
        while i < S.count {
            let charsToProcess = Swift.min(8, S.count - i)
            D = 0 // Reset accumulator for each 8-character block

            for j in 0..<charsToProcess {
                D <<= 5
                D |= UInt64(S[i+j])
            }
            
            // Adjust for the last block if it's shorter than 8 characters
            // The number of bits in the last block is charsToProcess * 5
            // We need to shift D left so the most significant bit of the data is at bit 39 (for 8 chars) or less
            let totalBits = charsToProcess * 5
            if charsToProcess < 8 {
                 D <<= (40 - totalBits)
            }

            var bytesInBlock = (totalBits / 8) // Integer division gives full bytes
            
            // Handle cases where totalBits is not a multiple of 8, e.g. 2 chars (10 bits -> 1 byte), 4 chars (20 bits -> 2 bytes)
            // 5 chars (25 bits -> 3 bytes), 7 chars (35 bits -> 4 bytes)
            // This is implicitly handled by how many bytes we extract below.
            // For OTP, common unpadded lengths are 16 (10 bytes), 32 (20 bytes)

            for _ in 0..<bytesInBlock {
                let byte = UInt8((D & 0xFF00000000) >> 32) // Extract the most significant byte
                data.append(byte)
                D <<= 8 // Shift left to process the next byte
            }
            i += 8 // Move to the next block of up to 8 Base32 characters
        }
        
        // Refined logic for extracting bytes based on RFC 4648, Table 3
        // This simplified loop above might miss nuances for partial last blocks.
        // A more correct approach for the main loop:
        var result = Data()
        var buffer: UInt64 = 0
        var bitsInBuffer: Int = 0

        for charValue in S {
            buffer = (buffer << 5) | UInt64(charValue)
            bitsInBuffer += 5

            if bitsInBuffer >= 8 {
                bitsInBuffer -= 8
                let byte = UInt8((buffer >> bitsInBuffer) & 0xFF)
                result.append(byte)
            }
        }
        
        // If the original simplified loop was problematic, replace `data` with `result`
        // For now, let's assume the refined logic is better.
        if result.isEmpty && !string.isEmpty { // If string was valid but result is empty, something is wrong.
             // This can happen if the input string length is too short to form a full byte, e.g. "AA" (10 bits)
             // RFC4648 implies that partial bytes at the end are ignored unless padding is used to signal them.
             // For OTP secrets, we generally expect full bytes.
             // If the simplified loop produced data, and this one didn't for short valid strings,
             // we might need to reconsider which one is more appropriate for unpadded OTP secrets.
             // However, the `result` approach is generally more robust for standard Base32.
        }
        
        self = result // Use the more robust decoding result
        if self.isEmpty && !string.isEmpty && string.count >= 2 { // Heuristic: if input was non-trivial but output is empty
            // This might indicate an issue with the decoding logic for certain valid short strings.
            // For OTP, secrets are typically long enough to avoid this.
            // print("Warning: Base32 decoding resulted in empty data for non-empty input: \(base32String)")
        }
    }
}
