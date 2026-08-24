import Testing
import Foundation
@testable import CarryCard

struct LoyaltyCardCodableTests {
    // `.iso8601` has whole-second precision, so round-trip comparisons must
    // start from a whole-second Date — `Date()` itself carries sub-second
    // precision that JSON encoding would silently truncate, making an exact
    // `==` comparison fail even though nothing is actually wrong.
    private static let wholeSecondDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func loyaltyCardRoundTripsThroughJSON() throws {
        let card = LoyaltyCard(
            name: "North Market",
            code: "6291041500213",
            barcodeType: .ean13,
            logoFileName: "logo.jpg",
            backgroundColor: CodableColor(red: 0.2, green: 0.4, blue: 0.6),
            sortIndex: 2,
            createdAt: Self.wholeSecondDate,
            updatedAt: Self.wholeSecondDate
        )

        let data = try CarryCardJSON.encoder.encode(card)
        let decoded = try CarryCardJSON.decoder.decode(LoyaltyCard.self, from: data)

        #expect(decoded == card)
    }

    @Test func loyaltyCardWithNilOptionalFieldsRoundTrips() throws {
        let card = LoyaltyCard(
            name: "Daily Club",
            code: "12345",
            barcodeType: .code128,
            createdAt: Self.wholeSecondDate,
            updatedAt: Self.wholeSecondDate
        )

        let data = try CarryCardJSON.encoder.encode(card)
        let decoded = try CarryCardJSON.decoder.decode(LoyaltyCard.self, from: data)

        #expect(decoded == card)
        #expect(decoded.logoFileName == nil)
        #expect(decoded.backgroundColor == nil)
    }

    @Test(arguments: BarcodeType.allCases)
    func barcodeTypeRoundTripsThroughJSON(type: BarcodeType) throws {
        let data = try CarryCardJSON.encoder.encode(type)
        let decoded = try CarryCardJSON.decoder.decode(BarcodeType.self, from: data)
        #expect(decoded == type)
    }

    @Test func barcodeTypeSerializesAsExpectedRawStrings() throws {
        let data = try CarryCardJSON.encoder.encode(BarcodeType.ean13)
        let string = String(data: data, encoding: .utf8)
        #expect(string == "\"ean13\"")
    }

    @Test func deletedCardRoundTripsThroughJSON() throws {
        let tombstone = DeletedCard(id: UUID(), deletedAt: Self.wholeSecondDate)
        let data = try CarryCardJSON.encoder.encode(tombstone)
        let decoded = try CarryCardJSON.decoder.decode(DeletedCard.self, from: data)
        #expect(decoded == tombstone)
    }
}
