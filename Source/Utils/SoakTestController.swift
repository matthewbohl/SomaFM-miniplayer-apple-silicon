#if SOAK_TEST
import Cocoa
import Darwin
import Foundation

@MainActor
final class SoakTestController {
    private struct Summary: Codable {
        let passed: Bool
        let stationID: String
        let requestedDurationSeconds: TimeInterval
        let completedCycles: Int
        let sampleCount: Int
        let analysis: SoakMemoryAnalysis
        let failures: [String]
    }

    private let configuration: SoakTestConfiguration
    private let menubarController: MenubarController
    private let fileManager = FileManager.default
    private var samples: [SoakMemorySample] = []
    private var failures: [String] = []
    private var startDate = Date()
    private var csvHandle: FileHandle?

    init(configuration: SoakTestConfiguration, menubarController: MenubarController) {
        self.configuration = configuration
        self.menubarController = menubarController
    }

    func start() {
        Task { @MainActor [weak self] in
            await self?.run()
        }
    }

    private func run() async {
        let defaults = UserDefaults.standard
        let originalStation = defaults.object(forKey: UserDefaultsKey.lastPlayedChannel)
        let originalPlayOnLaunch = defaults.object(forKey: UserDefaultsKey.shouldPlayOnLaunch)
        let originalNotifications = defaults.object(forKey: UserDefaultsKey.notificationsEnabled)

        do {
            try fileManager.createDirectory(
                at: configuration.resultsDirectory,
                withIntermediateDirectories: true
            )
            try openCSV()
            Settings.shouldPlayOnLaunch = false
            Settings.notificationsEnabled = false
            menubarController.radioPlayer.pause()
            startDate = Date()

            guard await waitForChannels() else {
                throw SoakFailure("Timed out waiting for the SomaFM channel list")
            }
            guard SomaAPI.channels?.contains(where: { $0.id == configuration.stationID }) == true else {
                throw SoakFailure("Station '\(configuration.stationID)' was not found")
            }

            Settings.lastPlayedChannelId = configuration.stationID
            let cycleDuration = configuration.duration / Double(configuration.cycles)
            for cycle in 1...configuration.cycles {
                try await runCycle(cycle, duration: cycleDuration)
            }
        } catch {
            failures.append(String(describing: error))
        }

        menubarController.radioPlayer.pause()
        recordSample(phase: "paused", cycle: configuration.cycles)
        restore(originalStation, forKey: UserDefaultsKey.lastPlayedChannel)
        restore(originalPlayOnLaunch, forKey: UserDefaultsKey.shouldPlayOnLaunch)
        restore(originalNotifications, forKey: UserDefaultsKey.notificationsEnabled)
        csvHandle?.closeFile()

        let analysis = SoakMemoryAnalysis.analyze(samples: samples)
        failures.append(contentsOf: analysis.failures(configuration: configuration))
        await coordinateLeakCheck()
        writeSummary(analysis: analysis)
        Darwin.exit(failures.isEmpty ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    private func runCycle(_ cycle: Int, duration: TimeInterval) async throws {
        guard menubarController.handlePlayCommand() else {
            throw SoakFailure("Cycle \(cycle): playback did not start")
        }
        try await samplePhase("playing", cycle: cycle, duration: duration * 0.40)

        guard menubarController.handlePauseCommand() else {
            throw SoakFailure("Cycle \(cycle): pause command failed")
        }
        try assertStreamDisposed(phase: "paused", cycle: cycle)
        try await samplePhase("paused", cycle: cycle, duration: duration * 0.30)

        guard menubarController.handlePlayCommand() else {
            throw SoakFailure("Cycle \(cycle): playback did not restart")
        }
        menubarController.radioPlayer.waitForNetwork()
        try assertStreamDisposed(phase: "network-wait", cycle: cycle)
        try await samplePhase("network-wait", cycle: cycle, duration: duration * 0.15)

        menubarController.radioPlayer.resumeAfterNetworkRecovery(channel: SomaAPI.lastPlayedChannel)
        guard menubarController.radioPlayer.hasActivePlayerItem else {
            throw SoakFailure("Cycle \(cycle): network recovery did not restore a stream")
        }
        if cycle < configuration.cycles && cycle.isMultiple(of: 5) {
            _ = menubarController.handleNextCommand()
        }
        try await samplePhase("recovered", cycle: cycle, duration: duration * 0.15)
    }

    private func samplePhase(_ phase: String, cycle: Int, duration: TimeInterval) async throws {
        let phaseEnd = Date().addingTimeInterval(duration)
        repeat {
            recordSample(phase: phase, cycle: cycle)
            if phase == "paused" || phase == "network-wait" {
                try assertStreamDisposed(phase: phase, cycle: cycle)
            }

            let remaining = phaseEnd.timeIntervalSinceNow
            guard remaining > 0 else { break }
            let delay = min(configuration.sampleInterval, remaining)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } while Date() < phaseEnd
    }

    private func waitForChannels() async -> Bool {
        let deadline = Date().addingTimeInterval(configuration.channelTimeout)
        while Date() < deadline {
            if SomaAPI.channels?.isEmpty == false { return true }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return false
    }

    private func assertStreamDisposed(phase: String, cycle: Int) throws {
        if menubarController.radioPlayer.hasActivePlayerItem {
            throw SoakFailure("Cycle \(cycle): active player item remained during \(phase)")
        }
    }

    private func openCSV() throws {
        let url = configuration.resultsDirectory.appendingPathComponent("samples.csv")
        fileManager.createFile(atPath: url.path, contents: nil)
        csvHandle = try FileHandle(forWritingTo: url)
        writeCSV("elapsed_seconds,resident_bytes,phase,cycle,player_state,has_active_player_item\n")
    }

    private func recordSample(phase: String, cycle: Int) {
        guard let residentBytes = residentMemoryBytes() else {
            failures.append("Unable to read resident memory")
            return
        }

        let sample = SoakMemorySample(
            elapsedSeconds: Date().timeIntervalSince(startDate),
            residentBytes: residentBytes,
            phase: phase,
            cycle: cycle,
            playerState: String(describing: menubarController.radioPlayer.state),
            hasActivePlayerItem: menubarController.radioPlayer.hasActivePlayerItem
        )
        samples.append(sample)
        writeCSV(
            "\(sample.elapsedSeconds),\(sample.residentBytes),\(sample.phase),\(sample.cycle)," +
            "\(sample.playerState),\(sample.hasActivePlayerItem)\n"
        )
    }

    private func residentMemoryBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    reboundPointer,
                    &count
                )
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : nil
    }

    private func coordinateLeakCheck() async {
        let readyURL = configuration.resultsDirectory.appendingPathComponent("ready-for-leak-check")
        let completeURL = configuration.resultsDirectory.appendingPathComponent("leak-check-complete")
        fileManager.createFile(atPath: readyURL.path, contents: nil)

        let deadline = Date().addingTimeInterval(configuration.leakCheckTimeout)
        while Date() < deadline {
            if fileManager.fileExists(atPath: completeURL.path) { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        failures.append("Timed out waiting for the external leak check")
    }

    private func writeSummary(analysis: SoakMemoryAnalysis) {
        let summary = Summary(
            passed: failures.isEmpty,
            stationID: configuration.stationID,
            requestedDurationSeconds: configuration.duration,
            completedCycles: samples.map(\.cycle).max() ?? 0,
            sampleCount: samples.count,
            analysis: analysis,
            failures: failures
        )
        let url = configuration.resultsDirectory.appendingPathComponent("summary.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(summary).write(to: url, options: .atomic)
    }

    private func writeCSV(_ line: String) {
        if let data = line.data(using: .utf8) {
            csvHandle?.write(data)
        }
    }

    private func restore(_ value: Any?, forKey key: String) {
        if let value = value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

private struct SoakFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
#endif
