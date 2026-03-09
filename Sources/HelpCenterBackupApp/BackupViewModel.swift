import Foundation

@MainActor
final class BackupViewModel: ObservableObject {
    @Published var logs: [String] = []
    @Published var isRunning = false
    @Published var statusLine = "Ready"
    @Published var lastStats: BackupStats?

    func startBackup(
        token: String,
        outputDirectoryPath: String,
        exportFormat: ExportFormat,
        includeImages: Bool,
        downloadMode: DownloadMode
    ) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = outputDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedToken.isEmpty else {
            statusLine = "Please provide an Intercom access token"
            return
        }

        guard !trimmedPath.isEmpty else {
            statusLine = "Please choose an output folder"
            return
        }

        let outputURL = URL(fileURLWithPath: trimmedPath)
        isRunning = true
        statusLine = "Running backup..."
        lastStats = nil
        logs.removeAll(keepingCapacity: true)

        Task {
            do {
                let stats = try await BackupEngine.run(
                    token: trimmedToken,
                    outputDirectory: outputURL,
                    exportFormat: exportFormat,
                    includeImages: includeImages,
                    downloadMode: downloadMode
                ) { [weak self] line in
                    Task { @MainActor in
                        self?.appendLog(line)
                    }
                }
                await MainActor.run {
                    self.lastStats = stats
                    self.statusLine = "Completed"
                    self.isRunning = false
                }
            } catch {
                await MainActor.run {
                    self.appendLog("Error: \(error.localizedDescription)")
                    self.statusLine = "Failed"
                    self.isRunning = false
                }
            }
        }
    }

    private func appendLog(_ line: String) {
        logs.append(line)
    }
}
