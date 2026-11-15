import Foundation

enum DocxWriter {
    // A minimal standards-based DOCX containing editable paragraphs, not a PDF facsimile.
    static func make(_ text: String) -> Data {
        func xml(_ string: String) -> String {
            let valid = string.unicodeScalars.filter { $0.value == 9 || $0.value == 10 || $0.value == 13 || ($0.value >= 32 && $0.value != 0xFFFE && $0.value != 0xFFFF) }
            return String(String.UnicodeScalarView(valid)).replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        let paragraphs = text.components(separatedBy: .newlines).map {
            "<w:p><w:r><w:t xml:space=\"preserve\">\(xml($0))</w:t></w:r></w:p>"
        }.joined()
        let files: [(String, String)] = [
            ("[Content_Types].xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/></Types>"),
            ("_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>"),
            ("word/document.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>\(paragraphs)<w:sectPr><w:pgSz w:w=\"12240\" w:h=\"15840\"/><w:pgMar w:top=\"1080\" w:right=\"1080\" w:bottom=\"1080\" w:left=\"1080\"/></w:sectPr></w:body></w:document>")
        ]
        var archive = Data(), directory = Data()
        for (name, content) in files {
            let filename = Data(name.utf8), body = Data(content.utf8), offset = UInt32(archive.count)
            let crc = crc32(body)
            archive.le(UInt32(0x04034b50)); archive.le(UInt16(20)); archive.le(UInt16(0x800))
            archive.le(UInt16(0)); archive.le(UInt16(0)); archive.le(UInt16(0x21))
            archive.le(crc); archive.le(UInt32(body.count)); archive.le(UInt32(body.count))
            archive.le(UInt16(filename.count)); archive.le(UInt16(0)); archive.append(filename); archive.append(body)
            directory.le(UInt32(0x02014b50)); directory.le(UInt16(20)); directory.le(UInt16(20))
            directory.le(UInt16(0x800)); directory.le(UInt16(0)); directory.le(UInt16(0)); directory.le(UInt16(0x21))
            directory.le(crc); directory.le(UInt32(body.count)); directory.le(UInt32(body.count))
            directory.le(UInt16(filename.count)); directory.le(UInt16(0)); directory.le(UInt16(0))
            directory.le(UInt16(0)); directory.le(UInt16(0)); directory.le(UInt32(0)); directory.le(offset)
            directory.append(filename)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        archive.le(UInt32(0x06054b50)); archive.le(UInt16(0)); archive.le(UInt16(0))
        archive.le(UInt16(files.count)); archive.le(UInt16(files.count)); archive.le(UInt32(directory.count))
        archive.le(directoryOffset); archive.le(UInt16(0))
        return archive
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) }
        }
        return ~crc
    }
}

private extension Data {
    mutating func le<T: FixedWidthInteger>(_ value: T) {
        var number = value.littleEndian
        Swift.withUnsafeBytes(of: &number) { append(contentsOf: $0) }
    }
}
