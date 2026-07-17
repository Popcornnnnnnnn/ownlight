import XCTest
@testable import PrivateMoments

final class APIErrorFallbackTests: XCTestCase {
    func testRouteNotFoundCanTryAlternateServerURL() {
        let error = APIError.httpStatus(
            404,
            #"{"message":"Route PUT:/api/v1/reviews/settings not found","error":"Not Found","statusCode":404}"#
        )

        XCTAssertTrue(error.shouldTryAlternateServerURL)
    }

    func testResourceNotFoundDoesNotTryAlternateServerURL() {
        let error = APIError.httpStatus(
            404,
            #"{"error":"not_found","message":"Review not found"}"#
        )

        XCTAssertFalse(error.shouldTryAlternateServerURL)
    }

    func testServerErrorCanTryAlternateServerURL() {
        XCTAssertTrue(APIError.httpStatus(503, "Service unavailable").shouldTryAlternateServerURL)
    }

    func testHTMLGatewayErrorDescriptionIsSanitized() {
        let error = APIError.httpStatus(
            502,
            #"<!DOCTYPE html><html><head><title>popcornnn.xyz | 502: Bad gateway</title></head><body>cloudflare</body></html>"#
        )

        XCTAssertEqual(
            error.localizedDescription,
            "HTTP 502: Bad gateway from server endpoint. Check the configured URL or tunnel."
        )
    }

    func testUnauthorizedDoesNotTryAlternateServerURL() {
        XCTAssertFalse(APIError.httpStatus(401, "Missing bearer token").shouldTryAlternateServerURL)
    }
}
