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
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.18, blue: 0.36),
                    Color(red: 0.06, green: 0.13, blue: 0.28),
                    Color(red: 0.04, green: 0.09, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.white.opacity(0.14), Color.clear],
                center: .top,
                startRadius: 20,
                endRadius: 700
            )
            .ignoresSafeArea()

            HStack(spacing: 0) {
                sidebar
                    .frame(width: 330)

                Divider().overlay(Color.white.opacity(0.2))

                terminalPanel
            }
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .padding(16)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                if let icon = appIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 42, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("HelpCenter Backup")
                        .font(.title3.weight(.semibold))
                    Text(appVersionText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
            }

            VStack(spacing: 8) {
                SidebarOptionRow(title: "Options", systemImage: "slider.horizontal.3", isActive: true)
                optionsPanel

                Button {
                    startBackup()
                } label: {
                    SidebarOptionRow(
                        title: viewModel.isRunning ? "Running Backup..." : "Run Backup",
                        systemImage: "play.fill",
                        isActive: true,
                        statusDotColor: canStartBackup ? .green : .red
                    )
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isRunning || !canStartBackup)
                .pointingHandCursor(enabled: !viewModel.isRunning && canStartBackup)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .foregroundStyle(.white)
    }

    private var optionsPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Intercom API Key")
                .foregroundStyle(.white.opacity(0.85))
                .font(.system(size: 12, weight: .medium))

            SecureField("Enter token", text: $accessToken)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )

            Text("Output Folder")
                .foregroundStyle(.white.opacity(0.85))
                .font(.system(size: 12, weight: .medium))
            HStack(spacing: 8) {
                TextField("Choose output directory", text: $outputPath)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

                Button("Browse") {
                    if let selected = chooseDirectory() {
                        outputPath = selected.path
                    }
                }
                .buttonStyle(.borderedProminent)
                .pointingHandCursor()
            }

            Text("File Type")
                .foregroundStyle(.white.opacity(0.85))
                .font(.system(size: 12, weight: .medium))
            Picker("", selection: exportFormatBinding) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .pointingHandCursor()

            Toggle("Include Images", isOn: $includeImages)
                .toggleStyle(.checkbox)
                .pointingHandCursor()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Full Download", isOn: fullDownloadBinding)
                    .toggleStyle(.checkbox)
                    .pointingHandCursor()
                Toggle("Updates Only", isOn: updatesOnlyBinding)
                    .toggleStyle(.checkbox)
                    .pointingHandCursor()
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var terminalPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(Color.red.opacity(0.9)).frame(width: 12, height: 12)
                Circle().fill(Color.yellow.opacity(0.9)).frame(width: 12, height: 12)
                Circle().fill(Color.green.opacity(0.9)).frame(width: 12, height: 12)

                Text("samuel@helpcenter-backup:~$ run backup")
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.leading, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(viewModel.logs.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                                    .foregroundStyle(logColor(for: line))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            if viewModel.logs.isEmpty {
                                Text("[Ready] Waiting to start backup...")
                                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.65))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(14)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )

                    HStack(spacing: 8) {
                        Text("$")
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan.opacity(0.9))
                        Text(viewModel.isRunning ? "backup running..." : "idle")
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 12) {
                    terminalStatCard(
                        title: "Current",
                        value: viewModel.statusLine,
                        subtitle: viewModel.isRunning ? "Backup in progress" : "Ready to run"
                    )

                    if let stats = viewModel.lastStats {
                        terminalStatCard(
                            title: "Results",
                            value: "New \(stats.created) • Updated \(stats.modified)",
                            subtitle: "Unchanged \(stats.unchanged) of \(stats.total)"
                        )
                    }
                }
                .frame(width: 250)
            }
        }
        .padding(14)
    }

    private var exportFormatBinding: Binding<ExportFormat> {
        Binding(
            get: { ExportFormat(rawValue: exportFormatRaw) ?? .markdown },
            set: { exportFormatRaw = $0.rawValue }
        )
    }

    private var fullDownloadBinding: Binding<Bool> {
        Binding(
            get: { (DownloadMode(rawValue: downloadModeRaw) ?? .updatesOnly) == .fullDownload },
            set: { isOn in
                downloadModeRaw = isOn ? DownloadMode.fullDownload.rawValue : DownloadMode.updatesOnly.rawValue
            }
        )
    }

    private var updatesOnlyBinding: Binding<Bool> {
        Binding(
            get: { (DownloadMode(rawValue: downloadModeRaw) ?? .updatesOnly) == .updatesOnly },
            set: { isOn in
                downloadModeRaw = isOn ? DownloadMode.updatesOnly.rawValue : DownloadMode.fullDownload.rawValue
            }
        )
    }

    private var canStartBackup: Bool {
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func startBackup() {
        guard canStartBackup else { return }
        viewModel.startBackup(
            token: accessToken,
            outputDirectoryPath: outputPath,
            exportFormat: ExportFormat(rawValue: exportFormatRaw) ?? .markdown,
            includeImages: includeImages,
            downloadMode: DownloadMode(rawValue: downloadModeRaw) ?? .updatesOnly
        )
    }

    private func terminalStatCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))

            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
    }

    private func logColor(for line: String) -> Color {
        if line.localizedCaseInsensitiveContains("error") || line.localizedCaseInsensitiveContains("failed") {
            return Color.red.opacity(0.95)
        }
        if line.localizedCaseInsensitiveContains("saved") || line.localizedCaseInsensitiveContains("finished") {
            return Color.green.opacity(0.95)
        }
        if line.localizedCaseInsensitiveContains("fetching") || line.localizedCaseInsensitiveContains("processing") {
            return Color.cyan.opacity(0.95)
        }
        return Color.white.opacity(0.88)
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

private struct SidebarOptionRow: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    var statusDotColor: Color? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 18)
            Text(title)
            Spacer()
            if let statusDotColor {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
            } else if isActive {
                Circle()
                    .fill(.cyan)
                    .frame(width: 8, height: 8)
            }
        }
        .foregroundStyle(.white.opacity(isActive ? 0.95 : 0.75))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isActive ? Color.cyan.opacity(0.20) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isActive ? Color.cyan.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private extension View {
    func pointingHandCursor(enabled: Bool = true) -> some View {
        onHover { isHovering in
            guard enabled else {
                NSCursor.arrow.set()
                return
            }
            if isHovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}
