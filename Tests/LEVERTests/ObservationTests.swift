import XCTest
import Observation
@testable import LEVER

@MainActor
final class ObservationTests: XCTestCase {
    func testSettingsMutationIsObserved() {
        let env = AppEnvironment.preview(seeded: false)
        var fired = false
        withObservationTracking {
            _ = env.settings.hasCompletedOnboarding
        } onChange: {
            fired = true
        }
        env.settings.hasCompletedOnboarding.toggle()
        XCTAssertTrue(fired)
        XCTAssertTrue(env.settings === env.repository.settings())
    }
}
