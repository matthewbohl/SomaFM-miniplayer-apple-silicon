import Foundation

struct SoakTestConfiguration: Equatable {
    enum ConfigurationError: Error, Equatable {
        case missingResultsDirectory
        case invalidValue(name: String, value: String)
    }

    let resultsDirectory: URL
    let duration: TimeInterval
    let cycles: Int
    let stationID: String
    let sampleInterval: TimeInterval
    let channelTimeout: TimeInterval
    let leakCheckTimeout: TimeInterval
    let maximumGrowthBytesPerHour: Double
    let maximumFinalGrowthBytes: UInt64
    let maximumFinalGrowthRatio: Double

    init(environment: [String: String]) throws {
        guard let path = environment["SOMAFM_SOAK_RESULTS_DIR"], !path.isEmpty else {
            throw ConfigurationError.missingResultsDirectory
        }

        resultsDirectory = URL(fileURLWithPath: path, isDirectory: true)
        duration = try Self.double("SOMAFM_SOAK_DURATION", default: 14_400, environment: environment)
        cycles = try Self.integer("SOMAFM_SOAK_CYCLES", default: 60, environment: environment)
        stationID = environment["SOMAFM_SOAK_STATION"] ?? "groovesalad"
        sampleInterval = try Self.double("SOMAFM_SOAK_SAMPLE_INTERVAL", default: 60, environment: environment)
        channelTimeout = try Self.double("SOMAFM_SOAK_CHANNEL_TIMEOUT", default: 60, environment: environment)
        leakCheckTimeout = try Self.double("SOMAFM_SOAK_LEAK_TIMEOUT", default: 120, environment: environment)

        let growthMBPerHour = try Self.double(
            "SOMAFM_SOAK_MAX_GROWTH_MB_PER_HOUR",
            default: 1,
            environment: environment
        )
        maximumGrowthBytesPerHour = growthMBPerHour * 1_048_576

        let finalGrowthMB = try Self.double(
            "SOMAFM_SOAK_MAX_FINAL_GROWTH_MB",
            default: 10,
            environment: environment
        )
        maximumFinalGrowthBytes = UInt64(finalGrowthMB * 1_048_576)
        maximumFinalGrowthRatio = try Self.double(
            "SOMAFM_SOAK_MAX_FINAL_GROWTH_RATIO",
            default: 0.10,
            environment: environment
        )

        guard cycles > 0 else {
            throw ConfigurationError.invalidValue(name: "SOMAFM_SOAK_CYCLES", value: String(cycles))
        }
        guard !stationID.isEmpty else {
            throw ConfigurationError.invalidValue(name: "SOMAFM_SOAK_STATION", value: stationID)
        }
    }

    private static func double(_ name: String,
                               default defaultValue: Double,
                               environment: [String: String]) throws -> Double {
        guard let rawValue = environment[name] else { return defaultValue }
        guard let value = Double(rawValue), value.isFinite, value > 0 else {
            throw ConfigurationError.invalidValue(name: name, value: rawValue)
        }
        return value
    }

    private static func integer(_ name: String,
                                default defaultValue: Int,
                                environment: [String: String]) throws -> Int {
        guard let rawValue = environment[name] else { return defaultValue }
        guard let value = Int(rawValue), value > 0 else {
            throw ConfigurationError.invalidValue(name: name, value: rawValue)
        }
        return value
    }
}

struct SoakMemorySample: Codable, Equatable {
    let elapsedSeconds: TimeInterval
    let residentBytes: UInt64
    let phase: String
    let cycle: Int
    let playerState: String
    let hasActivePlayerItem: Bool
}

struct SoakMemoryAnalysis: Codable, Equatable {
    let growthBytesPerHour: Double
    let baselinePausedBytes: UInt64?
    let finalPausedBytes: UInt64?
    let finalPausedGrowthBytes: UInt64?

    static func analyze(samples: [SoakMemorySample], warmupFraction: Double = 0.20) -> SoakMemoryAnalysis {
        guard let lastElapsed = samples.last?.elapsedSeconds else {
            return SoakMemoryAnalysis(
                growthBytesPerHour: 0,
                baselinePausedBytes: nil,
                finalPausedBytes: nil,
                finalPausedGrowthBytes: nil
            )
        }

        let warmupEnd = lastElapsed * warmupFraction
        let measuredSamples = samples.filter { $0.elapsedSeconds >= warmupEnd }
        let growth = linearGrowthBytesPerHour(samples: measuredSamples)
        let pausedSamples = samples.filter { $0.phase == "paused" }
        let baseline = pausedSamples.first?.residentBytes
        let final = pausedSamples.last?.residentBytes
        let finalGrowth = baseline.flatMap { baselineBytes in
            final.map { $0 > baselineBytes ? $0 - baselineBytes : 0 }
        }

        return SoakMemoryAnalysis(
            growthBytesPerHour: growth,
            baselinePausedBytes: baseline,
            finalPausedBytes: final,
            finalPausedGrowthBytes: finalGrowth
        )
    }

    func failures(configuration: SoakTestConfiguration) -> [String] {
        var failures: [String] = []

        if growthBytesPerHour > configuration.maximumGrowthBytesPerHour {
            failures.append("RSS growth exceeded the configured per-hour limit")
        }

        if let baseline = baselinePausedBytes, let finalGrowth = finalPausedGrowthBytes {
            let ratioLimit = UInt64(Double(baseline) * configuration.maximumFinalGrowthRatio)
            let permittedGrowth = max(configuration.maximumFinalGrowthBytes, ratioLimit)
            if finalGrowth > permittedGrowth {
                failures.append("Final paused RSS exceeded the configured growth limit")
            }
        }

        return failures
    }

    private static func linearGrowthBytesPerHour(samples: [SoakMemorySample]) -> Double {
        guard samples.count > 1 else { return 0 }

        let meanTime = samples.map(\.elapsedSeconds).reduce(0, +) / Double(samples.count)
        let meanBytes = samples.map { Double($0.residentBytes) }.reduce(0, +) / Double(samples.count)
        let numerator = samples.reduce(0.0) { result, sample in
            result + (sample.elapsedSeconds - meanTime) * (Double(sample.residentBytes) - meanBytes)
        }
        let denominator = samples.reduce(0.0) { result, sample in
            result + pow(sample.elapsedSeconds - meanTime, 2)
        }

        guard denominator > 0 else { return 0 }
        return max(0, numerator / denominator * 3_600)
    }
}
