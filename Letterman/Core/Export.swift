import Foundation
import UIKit
import libxlsxwriter

/// Builds an Excel spreadsheet of every hour log, with each supervisor's signature embedded as a picture.
enum Export {
    struct Failed: LocalizedError {
        var errorDescription: String? { "Couldn't create the spreadsheet. Try again." }
    }

    static func spreadsheet(logs: [HourLog], user: User) throws -> URL {
        let day = Date().formatted(.iso8601.year().month().day())
        let safeName = user.name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Volunteer-Hours-\(safeName.isEmpty ? "Export" : safeName)-\(day).xlsx")
        try? FileManager.default.removeItem(at: url)

        // libxlsxwriter needs a writable temp folder; the iOS sandbox only allows ours.
        let tmpdir = strdup(FileManager.default.temporaryDirectory.path)
        defer { free(tmpdir) }
        var options = lxw_workbook_options(constant_memory: 0, tmpdir: UnsafePointer(tmpdir), use_zip64: 0,
                                           output_buffer: nil, output_buffer_size: nil)
        guard let workbook = workbook_new_opt(url.path, &options) else { throw Failed() }
        let sheet = workbook_add_worksheet(workbook, "Volunteer hours")

        let title = workbook_add_format(workbook)
        format_set_bold(title)
        format_set_font_size(title, 16)
        let bold = workbook_add_format(workbook)
        format_set_bold(bold)
        let header = workbook_add_format(workbook)
        format_set_bold(header)
        format_set_bg_color(header, 0x123B2A)
        format_set_font_color(header, 0xFFFFFF)
        format_set_text_wrap(header)
        let top = workbook_add_format(workbook)
        format_set_text_wrap(top)
        format_set_align(top, UInt8(LXW_ALIGN_VERTICAL_TOP.rawValue))
        let date = workbook_add_format(workbook)
        format_set_num_format(date, "mmm d, yyyy h:mm AM/PM")
        format_set_align(date, UInt8(LXW_ALIGN_VERTICAL_TOP.rawValue))
        let number = workbook_add_format(workbook)
        format_set_num_format(number, "0.##")
        format_set_align(number, UInt8(LXW_ALIGN_VERTICAL_TOP.rawValue))

        let signedTotal = logs.filter(\.isSigned).reduce(0) { $0 + $1.hours }
        var school = [user.school, user.grade.isEmpty ? "" : "grade \(user.grade)"].filter { !$0.isEmpty }.joined(separator: ", ")
        if !school.isEmpty { school = " (\(school))" }
        worksheet_write_string(sheet, 0, 0, "Volunteer hours for \(user.name)\(school)", title)
        worksheet_write_string(sheet, 1, 0, "Exported \(Date().formatted(date: .long, time: .shortened)). Only signed hours count toward the total.", nil)

        let columns: [(String, Double)] = [
            ("Date and start time", 22), ("Hours", 8), ("Place", 26), ("Address", 28), ("Status", 12),
            ("Supervisor", 20), ("Signed on", 22), ("Comments", 40), ("Signature", 30),
        ]
        let headerRow: lxw_row_t = 3
        for (i, column) in columns.enumerated() {
            worksheet_set_column(sheet, lxw_col_t(i), lxw_col_t(i), column.1, nil)
            worksheet_write_string(sheet, headerRow, lxw_col_t(i), column.0, header)
        }
        worksheet_freeze_panes(sheet, headerRow + 1, 0)

        let signatureHeightPx = 70.0
        var row = headerRow + 1
        for log in logs.sorted(by: { $0.startedAt < $1.startedAt }) {
            var started = excelDate(log.startedAt)
            worksheet_write_datetime(sheet, row, 0, &started, date)
            worksheet_write_number(sheet, row, 1, log.hours, number)
            worksheet_write_string(sheet, row, 2, log.placeName, top)
            worksheet_write_string(sheet, row, 3, log.address, top)
            worksheet_write_string(sheet, row, 4, log.isSigned ? "Signed" : "Not signed", top)
            worksheet_write_string(sheet, row, 5, log.signerName, top)
            if var signed = log.signedDate.map(excelDate) {
                worksheet_write_datetime(sheet, row, 6, &signed, date)
            }
            worksheet_write_string(sheet, row, 7, log.comments, top)

            if let png = Data(base64Encoded: log.signature), let image = UIImage(data: png) {
                // Row height is in points (0.75 of a pixel).
                worksheet_set_row(sheet, row, signatureHeightPx * 0.75 + 8, nil)
                let pixelHeight = image.size.height * image.scale
                var imageOptions = lxw_image_options()
                imageOptions.x_offset = 4
                imageOptions.y_offset = 4
                imageOptions.x_scale = signatureHeightPx / pixelHeight
                imageOptions.y_scale = signatureHeightPx / pixelHeight
                let error = png.withUnsafeBytes { raw in
                    worksheet_insert_image_buffer_opt(sheet, row, 8, raw.bindMemory(to: UInt8.self).baseAddress,
                                                      png.count, &imageOptions)
                }
                if error != LXW_NO_ERROR { worksheet_write_string(sheet, row, 8, "(signature image missing)", top) }
            }
            row += 1
        }

        row += 1
        worksheet_write_string(sheet, row, 0, "Total signed hours", bold)
        worksheet_write_number(sheet, row, 1, signedTotal, bold)

        guard workbook_close(workbook) == LXW_NO_ERROR else { throw Failed() }
        return url
    }

    /// Excel dates have no time zone, so write the local wall-clock time the volunteer saw.
    private static func excelDate(_ date: Date) -> lxw_datetime {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return lxw_datetime(year: Int32(c.year!), month: Int32(c.month!), day: Int32(c.day!),
                            hour: Int32(c.hour!), min: Int32(c.minute!), sec: 0)
    }
}
