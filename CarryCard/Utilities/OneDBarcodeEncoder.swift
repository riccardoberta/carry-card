import Foundation

/// Produces the exact module-by-module bar/space pattern (as a string of `"1"` = bar,
/// `"0"` = space, one character per module) for the 1D symbologies that Core Image
/// cannot generate directly: EAN-13, EAN-8, UPC-E, Code 39 and Code 93.
///
/// Patterns are transcribed from the published symbology specifications (cross-checked
/// against the ZXing and python-barcode reference implementations) so that codes
/// rendered here decode correctly on standard retail scanners.
enum OneDBarcodeEncoder {

    enum EncodingError: Error {
        case invalidValue
    }

    // MARK: - EAN / UPC shared tables

    private static let eanEdge = "101"
    private static let eanMiddle = "01010"

    /// Left-hand "A" (odd parity) and right-hand "C" (even parity) digit patterns,
    /// each 7 modules. "B" is the even-parity mirror of "A", used for EAN-13's
    /// variable left-hand parity.
    private static let patternA: [String] = [
        "0001101", "0011001", "0010011", "0111101", "0100011",
        "0110001", "0101111", "0111011", "0110111", "0001011"
    ]
    private static let patternB: [String] = [
        "0100111", "0110011", "0011011", "0100001", "0011101",
        "0111001", "0000101", "0010001", "0001001", "0010111"
    ]
    private static let patternC: [String] = [
        "1110010", "1100110", "1101100", "1000010", "1011100",
        "1001110", "1010000", "1000100", "1001000", "1110100"
    ]

    /// For EAN-13, which pattern set (A/B) each of the 6 left-hand digits uses,
    /// indexed by the barcode's first digit.
    private static let leftPattern: [String] = [
        "AAAAAA", "AABABB", "AABBAB", "AABBBA", "ABAABB",
        "ABBAAB", "ABBBAA", "ABABAB", "ABABBA", "ABBABA"
    ]

    /// UPC-E parity tables (number system 0 and 1), indexed by check digit.
    /// "E" (even) selects `patternB`, "O" (odd) selects `patternA`.
    private static let upcEParityNS0: [String] = [
        "EEEOOO", "EEOEOO", "EEOOEO", "EEOOOE", "EOEEOO",
        "EOOEEO", "EOOOEE", "EOEOEO", "EOEOOE", "EOOEOE"
    ]
    private static let upcEParityNS1: [String] = [
        "OOOEEE", "OOEOEE", "OOEEOE", "OOEEEO", "OEOOEE",
        "OEEOOE", "OEEEOO", "OEOEOE", "OEOEEO", "OEEOEO"
    ]

    private static func mod10CheckDigit(_ digits: [Int]) -> Int {
        // Standard GS1 mod-10: from the rightmost digit, weights alternate 3, 1.
        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            sum += digit * (offset % 2 == 0 ? 3 : 1)
        }
        let remainder = sum % 10
        return remainder == 0 ? 0 : 10 - remainder
    }

    // MARK: - EAN-13

    /// `value` must be 12 or 13 digits. If 13, the check digit is verified by
    /// recomputation and always normalized (so an edited code renders correctly).
    static func ean13Pattern(value: String) throws -> String {
        let digits = try digitArray(value, allowedLengths: [12, 13])
        let payload = Array(digits.prefix(12))
        let check = mod10CheckDigit(payload)
        let full = payload + [check]

        var body = eanEdge
        let sides = Array(leftPattern[full[0]])
        for i in 0..<6 {
            let digit = full[i + 1]
            body += sides[i] == "A" ? patternA[digit] : patternB[digit]
        }
        body += eanMiddle
        for i in 0..<6 {
            body += patternC[full[i + 7]]
        }
        body += eanEdge
        return body
    }

    // MARK: - EAN-8

    static func ean8Pattern(value: String) throws -> String {
        let digits = try digitArray(value, allowedLengths: [7, 8])
        let payload = Array(digits.prefix(7))
        let check = mod10CheckDigit(payload)
        let full = payload + [check]

        var body = eanEdge
        for i in 0..<4 { body += patternA[full[i]] }
        body += eanMiddle
        for i in 0..<4 { body += patternC[full[i + 4]] }
        body += eanEdge
        return body
    }

    // MARK: - UPC-E

    /// `value` must be exactly 6 digits (the compressed payload). Number system
    /// digit defaults to 0, the common case for UPC-E.
    static func upceePattern(value: String, numberSystem: Int = 0) throws -> String {
        let digits = try digitArray(value, allowedLengths: [6])
        guard numberSystem == 0 || numberSystem == 1 else { throw EncodingError.invalidValue }

        let upcA = expandToUPCA(payload: digits, numberSystem: numberSystem)
        let check = mod10CheckDigit(Array(upcA.prefix(11)))

        let parityTable = numberSystem == 0 ? upcEParityNS0 : upcEParityNS1
        let parity = Array(parityTable[check])

        var body = eanEdge
        for i in 0..<6 {
            body += parity[i] == "E" ? patternB[digits[i]] : patternA[digits[i]]
        }
        body += "010101" // UPC-E end guard
        return body
    }

    /// Standard UPC-E -> UPC-A zero-suppression expansion (11 digits, check digit excluded).
    private static func expandToUPCA(payload: [Int], numberSystem: Int) -> [Int] {
        var result = [numberSystem]
        let d = payload
        switch d[5] {
        case 0, 1, 2:
            result += [d[0], d[1], d[5], 0, 0, 0, 0, d[2], d[3], d[4]]
        case 3:
            result += [d[0], d[1], d[2], 0, 0, 0, 0, 0, d[3], d[4]]
        case 4:
            result += [d[0], d[1], d[2], d[3], 0, 0, 0, 0, 0, d[4]]
        default:
            result += [d[0], d[1], d[2], d[3], d[4], 0, 0, 0, 0, d[5]]
        }
        return result
    }

    // MARK: - Code 39

    private static let code39Ref: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%")
    private static let code39Codes: [String] = [
        "101000111011101", "111010001010111", "101110001010111", "111011100010101",
        "101000111010111", "111010001110101", "101110001110101", "101000101110111",
        "111010001011101", "101110001011101", "111010100010111", "101110100010111",
        "111011101000101", "101011100010111", "111010111000101", "101110111000101",
        "101010001110111", "111010100011101", "101110100011101", "101011100011101",
        "111010101000111", "101110101000111", "111011101010001", "101011101000111",
        "111010111010001", "101110111010001", "101010111000111", "111010101110001",
        "101110101110001", "101011101110001", "111000101010111", "100011101010111",
        "111000111010101", "100010111010111", "111000101110101", "100011101110101",
        "100010101110111", "111000101011101", "100011101011101", "100010001000101",
        "100010001010001", "100010100010001", "101000100010001"
    ]
    private static let code39Edge = "100010111011101"
    private static let code39Middle = "0"

    /// Accepts uppercase letters, digits and `-. $/+%`. No checksum is added,
    /// matching the plain (non-Mod43) `.code39` scan result.
    static func code39Pattern(value: String) throws -> String {
        let upper = value.uppercased()
        var pieces = [code39Edge]
        for char in upper {
            guard let index = code39Ref.firstIndex(of: char) else { throw EncodingError.invalidValue }
            pieces.append(code39Codes[index])
        }
        guard pieces.count > 1 else { throw EncodingError.invalidValue }
        pieces.append(code39Edge)
        return pieces.joined(separator: code39Middle)
    }

    // MARK: - Code 93

    private static let code93BarChars: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%")
    /// Run-length width patterns (bar,space,bar,space,bar,space in modules) for
    /// indices 0...42 (data characters), 43...46 (shift characters, unused by us),
    /// 47 (start pattern) and 48 (stop pattern, includes the trailing termination bar).
    private static let code93Encodings: [String] = [
        "131112", "111213", "111312", "111411", "121113", "121212", "121311", "111114", "131211", "141111",
        "211113", "211212", "211311", "221112", "221211", "231111", "112113", "112212", "112311", "122112",
        "132111", "111123", "111222", "111321", "121122", "131121", "212112", "212211", "211122", "211221",
        "221121", "222111", "112122", "112221", "122121", "123111", "121131", "311112", "311211", "321111",
        "112131", "113121", "211131", "121221", "312111", "311121", "122211", "111141", "1111411"
    ]

    private static func expandRunLength(_ pattern: String) -> String {
        var result = ""
        var isBar = true
        for char in pattern {
            guard let count = char.wholeNumberValue else { continue }
            result += String(repeating: isBar ? "1" : "0", count: count)
            isBar.toggle()
        }
        return result
    }

    /// Accepts uppercase letters, digits and `-. $/+%`. Adds the standard two
    /// modulo-47 check characters (C then K) required for the symbol to validate.
    static func code93Pattern(value: String) throws -> String {
        let upper = value.uppercased()
        var indices: [Int] = []
        for char in upper {
            guard let index = code93BarChars.firstIndex(of: char) else { throw EncodingError.invalidValue }
            indices.append(index)
        }
        guard !indices.isEmpty else { throw EncodingError.invalidValue }

        let count = indices.count
        var checksumC = 0
        var checksumK = 0
        for (i, index) in indices.enumerated() {
            checksumC += (((count - i - 1) % 20) + 1) * index
            checksumK += (((count - i) % 15) + 1) * index
        }
        checksumC %= 47
        checksumK = (checksumK + checksumC) % 47

        var moduleString = expandRunLength(code93Encodings[47]) // start
        for index in indices { moduleString += expandRunLength(code93Encodings[index]) }
        moduleString += expandRunLength(code93Encodings[checksumC])
        moduleString += expandRunLength(code93Encodings[checksumK])
        moduleString += expandRunLength(code93Encodings[48]) // stop (includes termination bar)
        return moduleString
    }

    // MARK: - Shared helpers

    private static func digitArray(_ value: String, allowedLengths: [Int]) throws -> [Int] {
        guard allowedLengths.contains(value.count), let digits = value.wholeNumberDigits else {
            throw EncodingError.invalidValue
        }
        return digits
    }
}

private extension String {
    var wholeNumberDigits: [Int]? {
        var result: [Int] = []
        for char in self {
            guard let value = char.wholeNumberValue, value >= 0, value <= 9 else { return nil }
            result.append(value)
        }
        return result
    }
}
