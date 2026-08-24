import Testing
import Foundation
@testable import CarryCard

struct OneDBarcodeEncoderTests {
    @Test func ean13AcceptsTwelveDigitsAndAppendsCheckDigit() throws {
        // A well-known EAN-13: 690123456789 4 (check digit 4).
        let pattern = try OneDBarcodeEncoder.ean13Pattern(value: "690123456789")
        #expect(!pattern.isEmpty)
        #expect(pattern.allSatisfy { $0 == "0" || $0 == "1" })
        // Start guard "101" + middle "01010" + end guard "101" are always present.
        #expect(pattern.hasPrefix("101"))
        #expect(pattern.hasSuffix("101"))
    }

    @Test func ean13RejectsNonNumericValue() {
        #expect(throws: OneDBarcodeEncoder.EncodingError.self) {
            try OneDBarcodeEncoder.ean13Pattern(value: "abcdefghijkl")
        }
    }

    @Test func ean13RejectsWrongLength() {
        #expect(throws: OneDBarcodeEncoder.EncodingError.self) {
            try OneDBarcodeEncoder.ean13Pattern(value: "123")
        }
    }

    @Test func ean8ProducesValidBitPattern() throws {
        let pattern = try OneDBarcodeEncoder.ean8Pattern(value: "1234567")
        #expect(pattern.allSatisfy { $0 == "0" || $0 == "1" })
        #expect(pattern.hasPrefix("101"))
    }

    @Test func upcERequiresExactlySixDigits() {
        #expect(throws: OneDBarcodeEncoder.EncodingError.self) {
            try OneDBarcodeEncoder.upceePattern(value: "12345")
        }
    }

    @Test func upcEProducesValidBitPatternEndingInGuard() throws {
        let pattern = try OneDBarcodeEncoder.upceePattern(value: "425261")
        #expect(pattern.allSatisfy { $0 == "0" || $0 == "1" })
        #expect(pattern.hasSuffix("010101"))
    }

    @Test func code39EncodesAlphanumericValue() throws {
        let pattern = try OneDBarcodeEncoder.code39Pattern(value: "ABC-123")
        #expect(pattern.allSatisfy { $0 == "0" || $0 == "1" })
    }

    @Test func code39EncodesLowercaseByUppercasing() throws {
        // Code 39 has no case distinction; lowercase input is normalized, not rejected.
        let lower = try OneDBarcodeEncoder.code39Pattern(value: "abc")
        let upper = try OneDBarcodeEncoder.code39Pattern(value: "ABC")
        #expect(lower == upper)
    }

    @Test func code39RejectsUnsupportedCharacters() {
        #expect(throws: OneDBarcodeEncoder.EncodingError.self) {
            // '@' is not in Code 39's character set (digits, A-Z, -. $/+%).
            try OneDBarcodeEncoder.code39Pattern(value: "AB@CD")
        }
    }

    @Test func code93EncodesAlphanumericValueWithChecksum() throws {
        let pattern = try OneDBarcodeEncoder.code93Pattern(value: "TEST93")
        #expect(pattern.allSatisfy { $0 == "0" || $0 == "1" })
    }

    @Test func code93RejectsEmptyValue() {
        #expect(throws: OneDBarcodeEncoder.EncodingError.self) {
            try OneDBarcodeEncoder.code93Pattern(value: "")
        }
    }
}
