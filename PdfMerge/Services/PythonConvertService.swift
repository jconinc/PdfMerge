import Foundation
import os

enum PythonConvertService {

    // MARK: - Errors

    enum PythonError: LocalizedError {
        case pythonNotSetUp
        case scriptFailed(String)
        case cancelled

        var errorDescription: String? {
            switch self {
            case .pythonNotSetUp:
                return "The bundled Python environment is not set up. Please run the setup script first."
            case .scriptFailed(let detail):
                return "The conversion failed: \(detail)"
            case .cancelled:
                return "The conversion was cancelled."
            }
        }
    }

    // MARK: - Setup Check

    /// Path to the bundled Python environment inside the app bundle.
    private static var bundledPythonDirectory: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("python")
    }

    private static var pythonExecutable: URL {
        bundledPythonDirectory
            .appendingPathComponent("bin")
            .appendingPathComponent("python3")
    }

    /// Check whether the bundled Python environment exists and is executable.
    static func isSetUp() -> Bool {
        let pythonPath = pythonExecutable.path
        return FileManager.default.isExecutableFile(atPath: pythonPath)
    }

    // MARK: - Convert to Word

    /// Convert a PDF to a .docx Word document using the bundled Python + pdf2docx.
    /// - Parameters:
    ///   - inputURL: Source PDF file.
    ///   - outputURL: Destination .docx file.
    ///   - progress: Callback reporting (step, totalSteps).
    /// - Returns: The output URL.
    @discardableResult
    static func convertToWord(
        inputURL: URL,
        outputURL: URL,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> URL {
        guard isSetUp() else { throw PythonError.pythonNotSetUp }

        progress(1, 3)

        let script = """
        import sys
        from pdf2docx import Converter
        cv = Converter(sys.argv[1])
        cv.convert(sys.argv[2])
        cv.close()
        """

        progress(2, 3)

        try await runPythonScript(
            script: script,
            arguments: [inputURL.path, outputURL.path]
        )

        progress(3, 3)

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw PythonError.scriptFailed("Output file was not created.")
        }

        return outputURL
    }

    // MARK: - Convert to Excel

    /// Convert a PDF to an .xlsx Excel spreadsheet using the bundled Python + openpyxl.
    /// - Parameters:
    ///   - inputURL: Source PDF file.
    ///   - outputURL: Destination .xlsx file.
    ///   - progress: Callback reporting (step, totalSteps).
    /// - Returns: The output URL.
    @discardableResult
    static func convertToExcel(
        inputURL: URL,
        outputURL: URL,
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> URL {
        guard isSetUp() else { throw PythonError.pythonNotSetUp }

        progress(1, 3)

        // Use pdfplumber (or tabula) for table extraction + openpyxl for writing
        let script = """
        import sys
        import pdfplumber
        from openpyxl import Workbook

        pdf_path = sys.argv[1]
        xlsx_path = sys.argv[2]

        wb = Workbook()
        ws = wb.active
        ws.title = "Sheet1"

        with pdfplumber.open(pdf_path) as pdf:
            current_row = 1
            for page in pdf.pages:
                tables = page.extract_tables()
                for table in tables:
                    for row in table:
                        for col_idx, cell in enumerate(row):
                            ws.cell(row=current_row, column=col_idx + 1, value=cell or "")
                        current_row += 1
                    current_row += 1  # blank row between tables

        wb.save(xlsx_path)
        """

        progress(2, 3)

        try await runPythonScript(
            script: script,
            arguments: [inputURL.path, outputURL.path]
        )

        progress(3, 3)

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw PythonError.scriptFailed("Output file was not created.")
        }

        return outputURL
    }

    // MARK: - Private: Run Python Script

    private static func runPythonScript(
        script: String,
        arguments: [String]
    ) async throws {
        let process = Process()
        process.executableURL = pythonExecutable

        process.arguments = ["-c", script] + arguments

        var env = ProcessInfo.processInfo.environment
        env["PYTHONHOME"] = bundledPythonDirectory.path
        env["PYTHONPATH"] = bundledPythonDirectory
            .appendingPathComponent("lib")
            .appendingPathComponent("python3.11")
            .appendingPathComponent("site-packages")
            .path
        env.removeValue(forKey: "VIRTUAL_ENV")
        process.environment = env

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        let wasCancelled = OSAllocatedUnfairLock(initialState: false)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { proc in
                    if wasCancelled.withLock({ $0 }) {
                        continuation.resume(throwing: PythonError.cancelled)
                    } else if proc.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorMessage = String(data: errorData, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown error"
                        let lastLine = errorMessage.components(separatedBy: "\n").last ?? errorMessage
                        continuation.resume(throwing: PythonError.scriptFailed(lastLine))
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: PythonError.scriptFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            wasCancelled.withLock { $0 = true }
            if process.isRunning {
                process.terminate()
            }
        }
    }
}
