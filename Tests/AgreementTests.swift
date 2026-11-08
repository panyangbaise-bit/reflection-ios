import XCTest
@testable import PortfolioCore

final class AgreementTests: XCTestCase {
    func testLoginRequiresExplicitAgreement() throws {
        XCTAssertThrowsError(try AppAgreements.requireAcceptance(false))
        XCTAssertNoThrow(try AppAgreements.requireAcceptance(true))
    }

    func testReceiptPersistsVersionAndTimeWithoutGrantingAIConsent() throws {
        let name = "AgreementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertNil(AppAgreements.receipt(in: defaults))
        let date = Date(timeIntervalSince1970: 1234)
        AppAgreements.record(in: defaults, at: date)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: name))
        let receipt = try XCTUnwrap(AppAgreements.receipt(in: reopened))
        XCTAssertEqual(receipt.version, AppAgreements.version)
        XCTAssertEqual(receipt.acceptedAt, date)
        XCTAssertEqual(Set(reopened.persistentDomain(forName: name)?.keys.map { $0 } ?? []), [AppAgreements.storageKey])
    }

    func testUnreadableReceiptDoesNotImplyAcceptance() throws {
        let name = "AgreementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("invalid".utf8), forKey: AppAgreements.storageKey)
        XCTAssertNil(AppAgreements.receipt(in: defaults))
    }
}
