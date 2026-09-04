#if canImport(SwiftUI)
import Foundation
import SwiftUI

/// A one-tap front end for the probe.
///
/// It exists so the measurement ADR-006 requires can be taken on a real device without first
/// learning Xcode test targets and code signing. The numbers are the same numbers; this is only a
/// way to read them off a phone.
public struct ProbeView: View {

    @State private var results: [ProbeResult] = []
    @State private var running = false
    @State private var progress = ""
    @State private var failure: String?

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("THRØ durability probe")
                    .font(.title2.bold())

                Text("One durable transaction per visit, 200 visits per configuration. "
                     + "Budget: P95 ≤ 20 ms, P99 ≤ 50 ms.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                #if targetEnvironment(simulator)
                Label(
                    "Running in the Simulator. These numbers are your Mac's SSD, not a phone — "
                    + "they cannot answer this question. Run on a real device.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.orange)
                #endif

                Button(running ? "Measuring…" : "Run the probe") {
                    run()
                }
                .buttonStyle(.borderedProminent)
                .disabled(running)

                if running, !progress.isEmpty {
                    Text(progress).font(.footnote).foregroundStyle(.secondary)
                }

                if let failure {
                    Text(failure).font(.footnote).foregroundStyle(.red)
                }

                ForEach(results.indices, id: \.self) { i in
                    let r = results[i]
                    VStack(alignment: .leading, spacing: 6) {
                        Text(r.configuration.label)
                            .font(.subheadline.bold())
                        HStack {
                            stat("P50", r.p50)
                            stat("P95", r.p95)
                            stat("P99", r.p99)
                            stat("worst", r.worst)
                        }
                        Text(r.meetsBudget ? "meets the budget" : "EXCEEDS the budget")
                            .font(.caption.bold())
                            .foregroundStyle(r.meetsBudget ? .green : .red)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }

                if !results.isEmpty {
                    Text("The row that decides this is the one with fullfsync. On Apple platforms "
                         + "fsync does not flush the drive's write cache, so synchronous=FULL alone "
                         + "is not the barrier it looks like.\n\nIf that row exceeds the budget, "
                         + "ADR-006 says the durability rule wins and the budget is restated.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    private func stat(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(String(format: "%.2f", value)).font(.body.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }

    private func run() {
        running = true
        results = []
        failure = nil
        // Off the main thread: each configuration issues 200 real storage barriers, and blocking
        // the UI would make a slow device look like a hung app.
        DispatchQueue.global(qos: .userInitiated).async {
            var collected: [ProbeResult] = []
            for configuration in Durability.candidates {
                DispatchQueue.main.async { progress = "measuring \(configuration.label)…" }
                do {
                    collected.append(try Probe.measure(configuration, visits: 200))
                } catch {
                    DispatchQueue.main.async {
                        failure = "\(configuration.label): \(error)"
                    }
                }
            }
            // Also emit the table to stdout. The numbers go into ADR-006 as evidence, and reading
            // sixteen figures off a phone screen by hand is a transcription error waiting to
            // happen. `devicectl device process launch --console` captures this, so the recorded
            // figures are the ones the device actually produced.
            Probe.printReport(collected)

            DispatchQueue.main.async {
                results = collected
                running = false
                progress = ""
            }
        }
    }
}
#endif
