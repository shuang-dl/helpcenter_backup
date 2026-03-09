import AppKit
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = BackupViewModel()

    @AppStorage("helpCenterBackup.token") private var accessToken = ""
    @AppStorage("helpCenterBackup.outputPath") private var outputPath = ""
    @AppStorage("helpCenterBackup.exportFormat") private var exportFormatRaw = ExportFormat.markdown.rawValue
    @AppStorage("helpCenterBackup.includeImages") private var includeImages = true
    @AppStorage("helpCenterBackup.downloadMode") private var downloadModeRaw = DownloadMode.updatesOnly.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    if let icon = appIconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Text(appVersionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 64, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Help Center Backup")
                        .font(.title2)
                        .bold()

                    Text("Download an incremental backup of your Intercom help center articles.")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Intercom Access Token")
                    SecureField("Enter Intercom API key", text: $accessToken)
                        .textFieldStyle(.roundedBorder)

                    Text("Output Folder")
                    HStack {
                        TextField("Choose output directory", text: $outputPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse...") {
                            if let selected = chooseDirectory() {
                                outputPath = selected.path
                            }
                        }
                    }

                    Text("File Type")
                    Picker("", selection: Binding(
                        get: { ExportFormat(rawValue: exportFormatRaw) ?? .markdown },
                        set: { exportFormatRaw = $0.rawValue }
                    )) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 180, alignment: .leading)

                    Toggle("Include Images", isOn: $includeImages)
                        .toggleStyle(.checkbox)

                    HStack(spacing: 18) {
                        Toggle("Full Download", isOn: Binding(
                            get: { (DownloadMode(rawValue: downloadModeRaw) ?? .updatesOnly) == .fullDownload },
                            set: { isOn in
                                downloadModeRaw = isOn ? DownloadMode.fullDownload.rawValue : DownloadMode.updatesOnly.rawValue
                            }
                        ))
                        .toggleStyle(.checkbox)

                        Toggle("Updates Only", isOn: Binding(
                            get: { (DownloadMode(rawValue: downloadModeRaw) ?? .updatesOnly) == .updatesOnly },
                            set: { isOn in
                                downloadModeRaw = isOn ? DownloadMode.updatesOnly.rawValue : DownloadMode.fullDownload.rawValue
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.top, 4)
            }

            HStack {
                Button(viewModel.isRunning ? "Running..." : "Start Backup") {
                    viewModel.startBackup(
                        token: accessToken,
                        outputDirectoryPath: outputPath,
                        exportFormat: ExportFormat(rawValue: exportFormatRaw) ?? .markdown,
                        includeImages: includeImages,
                        downloadMode: DownloadMode(rawValue: downloadModeRaw) ?? .updatesOnly
                    )
                }
                .disabled(viewModel.isRunning)

                Text(viewModel.statusLine)
                    .foregroundStyle(.secondary)
            }

            if let stats = viewModel.lastStats {
                Text("Total: \(stats.total)   New: \(stats.created)   Modified: \(stats.modified)   Unchanged: \(stats.unchanged)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }

            GroupBox("Run Log") {
                ScrollViewReader { _ in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(viewModel.logs.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(8)
                    }
                    .background(Color(NSColor.textBackgroundColor))
                }
            }
        }
        .padding(18)
    }

    private var appIconImage: NSImage? {
        NSImage(named: "AppIcon") ?? NSApplication.shared.applicationIconImage
    }

    private var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let shortVersion = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "v\(shortVersion) (\(build))"
    }

    private func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
