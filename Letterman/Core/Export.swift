import Foundation
import UIKit
import libxlsxwriter

/// Builds an Excel spreadsheet of every hour log, with each supervisor's signature embedded as a picture.
enum Export {
    struct Failed: LocalizedError {
        var errorDescription: String? = "Couldn't create the export. Try again."
    }

    /// "Volunteer-Hours-Maya-Chen-2026-10-11.pdf" in the temporary folder, replacing an older copy.
    private static func file(for user: User, _ ext: String) -> URL {
        let day = Date().formatted(.iso8601.year().month().day())
        let safeName = user.name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Volunteer-Hours-\(safeName.isEmpty ? "Export" : safeName)-\(day).\(ext)")
        try? FileManager.default.removeItem(at: url)
        return url
    }

    /// A report for a school: signed hours only (unsigned ones don't count), each with its signature.
    static func pdf(logs: [HourLog], user: User) throws -> URL {
        let signed = logs.filter(\.isSigned).sorted { $0.startedAt < $1.startedAt }
        guard !signed.isEmpty else { throw Failed(errorDescription: "There are no signed hours to put in a report yet.") }
        let url = file(for: user, "pdf")

        let page = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter, in points
        let margin: CGFloat = 54
        let width = page.width - margin * 2
        let rowHeight: CGFloat = 84
        let gray = UIColor(white: 0.4, alpha: 1)
        let forest = UIColor(red: 0x12 / 255, green: 0x3B / 255, blue: 0x2A / 255, alpha: 1)
        let font = { (size: CGFloat, weight: UIFont.Weight) in UIFont.systemFont(ofSize: size, weight: weight) }

        func draw(_ text: String, in rect: CGRect, _ font: UIFont, _ color: UIColor = .black, _ align: NSTextAlignment = .left) {
            let style = NSMutableParagraphStyle()
            style.alignment = align
            style.lineBreakMode = .byWordWrapping // wraps when the box has room for more lines, else "…" on the last one
            (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                    attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style], context: nil)
        }
        func line(at y: CGFloat, _ color: UIColor = UIColor(white: 0.85, alpha: 1)) {
            color.setFill()
            UIRectFill(CGRect(x: margin, y: y, width: width, height: 0.75))
        }

        let total = signed.reduce(0) { $0 + $1.hours }
        var school = [user.school, user.grade.isEmpty ? "" : "grade \(user.grade)"].filter { !$0.isEmpty }.joined(separator: ", ")
        if school.isEmpty { school = user.email }

        let data = UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            var pageNumber = 0
            var y: CGFloat = 0
            func newPage() {
                context.beginPage()
                pageNumber += 1
                draw("Letterman volunteer hours report · Page \(pageNumber)", in: CGRect(x: margin, y: page.height - 40, width: width, height: 14),
                     font(8, .regular), gray)
                y = margin
                if pageNumber == 1 {
                    draw("Volunteer hours", in: CGRect(x: margin, y: y, width: width, height: 30), font(24, .bold), forest)
                    draw(user.name, in: CGRect(x: margin, y: y + 34, width: width, height: 20), font(14, .semibold))
                    draw(school, in: CGRect(x: margin, y: y + 54, width: width, height: 16), font(11, .regular), gray)
                    draw("\(total.hoursText) signed \(total == 1 ? "hour" : "hours")", in: CGRect(x: margin, y: y, width: width, height: 30),
                         font(20, .bold), forest, .right)
                    draw("Exported \(Date().formatted(date: .long, time: .omitted))", in: CGRect(x: margin, y: y + 34, width: width, height: 16),
                         font(10, .regular), gray, .right)
                    y += 80
                    draw("Only hours signed by the person in charge are included. Signed entries are locked and can't be edited.",
                         in: CGRect(x: margin, y: y, width: width, height: 14), font(9, .regular), gray)
                    y += 22
                }
                draw("DATE", in: CGRect(x: margin, y: y, width: 100, height: 12), font(8, .bold), gray)
                draw("PLACE AND SUPERVISOR", in: CGRect(x: margin + 108, y: y, width: 220, height: 12), font(8, .bold), gray)
                draw("HOURS", in: CGRect(x: margin + 330, y: y, width: 44, height: 12), font(8, .bold), gray, .right)
                draw("SIGNATURE", in: CGRect(x: margin + 386, y: y, width: width - 386, height: 12), font(8, .bold), gray)
                y += 16
                line(at: y, forest)
                y += 8
            }

            newPage()
            for log in signed {
                if y + rowHeight > page.height - 56 { newPage() }
                draw(log.startedAt.formatted(date: .abbreviated, time: .omitted), in: CGRect(x: margin, y: y, width: 100, height: 14), font(10, .semibold))
                draw(log.startedAt.formatted(date: .omitted, time: .shortened), in: CGRect(x: margin, y: y + 14, width: 100, height: 14), font(9, .regular), gray)
                draw(log.placeName, in: CGRect(x: margin + 108, y: y, width: 220, height: 14), font(10, .semibold))
                draw(log.address, in: CGRect(x: margin + 108, y: y + 14, width: 220, height: 13), font(9, .regular), gray)
                draw(log.comments, in: CGRect(x: margin + 108, y: y + 27, width: 220, height: 24), font(9, .regular), gray)
                let signedOn = log.signedDate.map { " on \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
                draw("\(log.isConfirmed ? "Confirmed" : "Signed") by \(log.signerName)\(signedOn)", in: CGRect(x: margin + 108, y: y + 53, width: 220, height: 24), font(9, .medium), forest)
                draw(log.hours.hoursText, in: CGRect(x: margin + 330, y: y, width: 44, height: 18), font(13, .bold), .black, .right)
                if let image = log.signatureImage {
                    let box = CGRect(x: margin + 386, y: y, width: width - 386, height: 60)
                    let scale = min(box.width / image.size.width, box.height / image.size.height, 1)
                    image.draw(in: CGRect(x: box.minX, y: box.minY, width: image.size.width * scale, height: image.size.height * scale))
                } else if log.isConfirmed {
                    draw("Attendance confirmed by the organization in Letterman", in: CGRect(x: margin + 386, y: y + 2, width: width - 386, height: 40),
                         font(9, .medium), forest)
                }
                y += rowHeight - 8
                line(at: y)
                y += 8
            }
        }
        do {
            try data.write(to: url)
        } catch {
            throw Failed()
        }
        return url
    }

    static func spreadsheet(logs: [HourLog], user: User) throws -> URL {
        let url = file(for: user, "xlsx")

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
            worksheet_write_string(sheet, row, 4, log.isConfirmed ? "Confirmed" : log.isSigned ? "Signed" : "Not signed", top)
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
            } else if log.isConfirmed {
                worksheet_write_string(sheet, row, 8, "Attendance confirmed by the organization in Letterman", top)
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
