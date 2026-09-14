import Foundation

nonisolated enum WSError: LocalizedError {
    case notAWiiOrGameCubeDisc
    case keyMissing(String)
    case ioError(String)
    case notImplemented(String)
    case badStructure(String)

    var errorDescription: String? {
        switch self {
        case .notAWiiOrGameCubeDisc: return "This does not look like a Wii or GameCube disc image."
        case .keyMissing(let s): return "Missing key: \(s)"
        case .ioError(let s): return "I/O error: \(s)"
        case .notImplemented(let s): return "Not implemented: \(s)"
        case .badStructure(let s): return "Bad disc structure: \(s)"
        }
    }
}

/// Big-endian helpers for the fixed-width integers used throughout the Wii/GC disc formats.
nonisolated extension Data {
    func be32(_ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        let b = self
        let i0 = b[b.startIndex + offset]
        let i1 = b[b.startIndex + offset + 1]
        let i2 = b[b.startIndex + offset + 2]
        let i3 = b[b.startIndex + offset + 3]
        return (UInt32(i0) << 24) | (UInt32(i1) << 16) | (UInt32(i2) << 8) | UInt32(i3)
    }

    func be16(_ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        let b = self
        let i0 = b[b.startIndex + offset]
        let i1 = b[b.startIndex + offset + 1]
        return (UInt16(i0) << 8) | UInt16(i1)
    }

    func u8(_ offset: Int) -> UInt8 {
        guard offset >= 0, offset < count else { return 0 }
        return self[self.startIndex + offset]
    }

    /// 32-bit big endian value that represents an offset stored right-shifted by 2 (used pervasively
    /// in the Wii disc format so 32-bit fields can address up to 16GB).
    func be32Shifted(_ offset: Int) -> UInt64 {
        UInt64(be32(offset)) << 2
    }

    func be64(_ offset: Int) -> UInt64 {
        guard offset >= 0, offset + 8 <= count else { return 0 }
        var v: UInt64 = 0
        for i in 0..<8 { v = (v << 8) | UInt64(self[self.startIndex + offset + i]) }
        return v
    }

    func subdata(at offset: Int, length: Int) -> Data {
        guard offset >= 0, length >= 0, offset + length <= count else { return Data() }
        return subdata(in: (startIndex + offset)..<(startIndex + offset + length))
    }

    func asciiString(at offset: Int, length: Int) -> String {
        let d = subdata(at: offset, length: length)
        let bytes = [UInt8](d).prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// Small helper for building up big-endian binary structures.
nonisolated final class MutableDataWriter {
    private(set) var data: Data

    init(_ initial: Data = Data()) { data = initial }

    func putU8(_ v: UInt8) { data.append(v) }

    func putU16(_ v: UInt16) {
        data.append(UInt8((v >> 8) & 0xFF))
        data.append(UInt8(v & 0xFF))
    }

    func putU32(_ v: UInt32) {
        data.append(UInt8((v >> 24) & 0xFF))
        data.append(UInt8((v >> 16) & 0xFF))
        data.append(UInt8((v >> 8) & 0xFF))
        data.append(UInt8(v & 0xFF))
    }

    func putU32Shifted(_ v: UInt64) { putU32(UInt32(truncatingIfNeeded: v >> 2)) }

    func putU64(_ v: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) {
            data.append(UInt8((v >> UInt64(shift)) & 0xFF))
        }
    }

    func putData(_ d: Data) { data.append(d) }

    func pad(to length: Int, with byte: UInt8 = 0) {
        if data.count < length { data.append(Data(repeating: byte, count: length - data.count)) }
    }
}

/// Thin wrapper around FileHandle for random access reads/writes with clearer call sites,
/// and to centralize error handling.
nonisolated final class RandomAccessFile {
    let handle: FileHandle
    let url: URL

    init(forReadingFrom url: URL) throws {
        self.url = url
        self.handle = try FileHandle(forReadingFrom: url)
    }

    init(forUpdating url: URL) throws {
        self.url = url
        self.handle = try FileHandle(forUpdating: url)
    }

    func read(at offset: UInt64, count: Int) throws -> Data {
        try handle.seek(toOffset: offset)
        guard let d = try handle.read(upToCount: count) else { return Data() }
        return d
    }

    func write(_ data: Data, at offset: UInt64) throws {
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: data)
    }

    func fileSize() throws -> UInt64 {
        let cur = handle.offsetInFile
        try handle.seekToEnd()
        let end = handle.offsetInFile
        try handle.seek(toOffset: cur)
        return end
    }

    func close() {
        try? handle.close()
    }
}
