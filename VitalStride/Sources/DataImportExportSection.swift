// swiftlint:disable no_hardcoded_chinese
// Rationale: All CJK literals in this file are wrapped in String(localized:) for i18n;
// the regex-based rule can't distinguish that from a raw literal (MY-1269).
import DesignKit
import SwiftUI
import TelemetryKit
import UniformTypeIdentifiers

struct DataImportExportSection: View {
    @Environment(\.theme) private var theme
    @State private var showingFileImporter = false
    @State private var showingFileExporter = false
    @State private var importedFiles: [ImportedFileRecord] = []
    @State private var importError: String?
    @State private var exportError: String?
    @State private var exportRange: ExportRange = .all

    var body: some View {
        Section(String(localized: "数据导入", comment: "")) {
            Button {
                showingFileImporter = true
            } label: {
                Label(String(localized: "导入 GPX/FIT 文件", comment: ""), systemImage: "square.and.arrow.down")
                    .tint(theme.primary.primary)
            }

            if !importedFiles.isEmpty {
                DisclosureGroup {
                    ForEach(importedFiles) { file in
                        HStack {
                            Text(file.fileName)
                                .font(.subheadline)
                            Spacer()
                            Text(file.importDate, style: .date)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(theme.neutrals.text2)
                        }
                    }
                } label: {
                    Label(String(localized: "导入历史 (\(importedFiles.count))", comment: "Import history menu label with count"), systemImage: "clock")
                        .tint(theme.primary.primary)
                }
            }

            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(theme.danger)
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.gpx, .fit],
            allowsMultipleSelection: true
        ) { result in
            handleImportResult(result)
        }

        Section(String(localized: "数据导出", comment: "")) {
            Picker(selection: $exportRange) {
                ForEach(ExportRange.allCases, id: \.self) { range in
                    Text(range.displayName).tag(range)
                }
            } label: {
                Label(String(localized: "导出范围", comment: ""), systemImage: "calendar")
                    .tint(theme.primary.primary)
            }

            Button {
                showingFileExporter = true
            } label: {
                Label(String(localized: "导出训练数据 (JSON)", comment: ""), systemImage: "square.and.arrow.up")
                    .tint(theme.primary.primary)
            }
        }
        .fileExporter(
            isPresented: $showingFileExporter,
            document: ExportDocument(content: "{}"),
            contentType: .json,
            defaultFilename: "VitalStride-Export.json"
        ) { result in
            handleExportResult(result)
        }
        .alert(String(localized: "导出失败", comment: ""), isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button(String(localized: "确定", comment: ""), role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private func handleImportResult(_ result: Result<[URL], any Error>) {
        importError = nil
        switch result {
        case .success(let urls):
            let newRecords = urls.map { url in
                ImportedFileRecord(
                    fileName: url.lastPathComponent,
                    importDate: Date()
                )
            }
            importedFiles = importedFiles + newRecords
            for url in urls {
                let ext = url.pathExtension.lowercased()
                let format: TelemetryIdentifier
                switch ext {
                case "gpx": format = "gpx"
                case "fit": format = "fit"
                default: continue
                }
                TelemetryService.shared.trackNonisolated(.dataImported(format: format))
            }
        case .failure(let error):
            importError = String(localized: "导入失败: \(error.localizedDescription)", comment: "Import failure with error detail")
        }
    }

    private func handleExportResult(_ result: Result<URL, any Error>) {
        switch result {
        case .success:
            exportError = nil
        case .failure(let error):
            exportError = error.localizedDescription
        }
    }
}

struct ImportedFileRecord: Identifiable {
    let id = UUID()
    let fileName: String
    let importDate: Date
}

enum ExportRange: String, CaseIterable {
    case all
    case lastMonth
    case lastThreeMonths
    case lastYear

    var displayName: String {
        switch self {
        case .all: return String(localized: "全部", comment: "")
        case .lastMonth: return String(localized: "最近一个月", comment: "")
        case .lastThreeMonths: return String(localized: "最近三个月", comment: "")
        case .lastYear: return String(localized: "最近一年", comment: "")
        }
    }
}

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let content: String

    init(content: String) {
        self.content = content
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            content = String(data: data, encoding: .utf8) ?? "{}"
        } else {
            content = "{}"
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(content.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static let gpx = UTType(filenameExtension: "gpx") ?? .xml
    static let fit = UTType(filenameExtension: "fit") ?? .data
}

#Preview {
    Form {
        DataImportExportSection()
    }
    .designThemePreview()
}
