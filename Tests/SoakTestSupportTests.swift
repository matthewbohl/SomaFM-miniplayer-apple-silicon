import XCTest
@testable import SomaFM_miniplayer

final class SoakTestSupportTests: XCTestCase {
    func testConfigurationUsesDocumentedDefaults() throws {
        let configuration = try SoakTestConfiguration(environment: [
            "SOMAFM_SOAK_RESULTS_DIR": "/private/tmp/soak-results"
        ])

        XCTAssertEqual(configuration.duration, 14_400)
        XCTAssertEqual(configuration.cycles, 60)
        XCTAssertEqual(configuration.stationID, "groovesalad")
        XCTAssertEqual(configuration.sampleInterval, 60)
        XCTAssertEqual(configuration.maximumGrowthBytesPerHour, 1_048_576)
        XCTAssertEqual(configuration.maximumFinalGrowthBytes, 10 * 1_048_576)
        XCTAssertEqual(configuration.maximumFinalGrowthRatio, 0.10)
    }

    func testConfigurationRejectsInvalidNumericValue() {
        XCTAssertThrowsError(try SoakTestConfiguration(environment: [
            "SOMAFM_SOAK_RESULTS_DIR": "/private/tmp/soak-results",
            "SOMAFM_SOAK_CYCLES": "zero"
        ])) { error in
            XCTAssertEqual(
                error as? SoakTestConfiguration.ConfigurationError,
                .invalidValue(name: "SOMAFM_SOAK_CYCLES", value: "zero")
            )
        }
    }

    func testMemoryAnalysisCalculatesLinearHourlyGrowth() {
        let samples = [
            sample(seconds: 0, bytes: 10_000, phase: "paused"),
            sample(seconds: 1_800, bytes: 10_500, phase: "playing"),
            sample(seconds: 3_600, bytes: 11_000, phase: "paused")
        ]

        let analysis = SoakMemoryAnalysis.analyze(samples: samples, warmupFraction: 0)

        XCTAssertEqual(analysis.resident.growthBytesPerHour, 1_000, accuracy: 0.001)
        XCTAssertEqual(analysis.resident.baselinePausedBytes, 10_000)
        XCTAssertEqual(analysis.resident.finalPausedBytes, 11_000)
        XCTAssertEqual(analysis.resident.finalPausedGrowthBytes, 1_000)
        XCTAssertEqual(analysis.physicalFootprint.growthBytesPerHour, 500, accuracy: 0.001)
    }

    func testMemoryAnalysisReportsThresholdFailures() throws {
        let configuration = try SoakTestConfiguration(environment: [
            "SOMAFM_SOAK_RESULTS_DIR": "/private/tmp/soak-results",
            "SOMAFM_SOAK_MAX_GROWTH_MB_PER_HOUR": "0.0001",
            "SOMAFM_SOAK_MAX_FINAL_GROWTH_MB": "0.0001",
            "SOMAFM_SOAK_MAX_FINAL_GROWTH_RATIO": "0.01"
        ])
        let analysis = SoakMemoryAnalysis(
            resident: SoakMemoryMetricAnalysis(
                growthBytesPerHour: 100_000,
                baselinePausedBytes: 10_000,
                finalPausedBytes: 110_000,
                finalPausedGrowthBytes: 100_000
            ),
            physicalFootprint: SoakMemoryMetricAnalysis(
                growthBytesPerHour: 1_000,
                baselinePausedBytes: 10_000,
                finalPausedBytes: 11_000,
                finalPausedGrowthBytes: 1_000
            )
        )

        XCTAssertEqual(analysis.failures(configuration: configuration).count, 2)
    }

    private func sample(seconds: TimeInterval, bytes: UInt64, phase: String) -> SoakMemorySample {
        SoakMemorySample(
            elapsedSeconds: seconds,
            residentBytes: bytes,
            physicalFootprintBytes: bytes / 2,
            phase: phase,
            cycle: 1,
            playerState: "stopped",
            hasActivePlayerItem: false,
            streamStartCount: 1,
            streamDiscardCount: 1
        )
    }
}
