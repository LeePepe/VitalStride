import SwiftUI
import UniformTypeIdentifiers

struct DataImportExportSection: View {
    @State private var showingFileImporter = false
    @State private var showingFileExporter = false
    @State private var importedFiles: [ImportedFileRecord] = []
    @State private var importError: String?
    @State private var exportError: String?
    @State private var exportRange: ExportRange = .all

    var body: some View {
        Section("数据导入") {
            Button {
                showingFileImporter = true
            } label: {
                Label("导入 GPX/FIT 文件", systemImage: "square.and.arrow.down")
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
                                .foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    Label("导入历史 (\(importedFiles.count))", systemImage: "clock")
                }
            }

            if let importError {
                Label(importError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.gpx, .fit],
            allowsMultipleSelection: true
        ) { result in
            handleImportResult(result)
        }

        Section("数据导出") {
            Picker(selection: $exportRange) {
                ForEach(ExportRange.allCases, id: \.self) { range in
                    Text(range.displayName).tag(range)
                }
            } label: {
                Label("导出范围", systemImage: "calendar")
            }

            Button {
                showingFileExporter = true
            } label: {
                Label("导出训练数据 (JSON)", systemImage: "square.and.arrow.up")
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
        .alert("导出失败", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("确定", role: .cancel) {}
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
        case .failure(let error):
            importError = "导入失败: \(error.localizedDescription)"
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
        case .all: return "全部"
        case .lastMonth: return "最近一个月"
        case .lastThreeMonths: return "最近三个月"
        case .lastYear: return "最近一年"
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
}
