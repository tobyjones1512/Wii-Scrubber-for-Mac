import Foundation

/// Minimal read-only GameCube disc support: browse and extract only. Matches the original tool's
/// own limitation (FAQ Q11: "Does Load work on Gamecube discs? No. As all the work is based
/// around encrypted partitions.") -- GC discs have no encryption/partitions at all, so replace
/// isn't meaningful in the same way and isn't offered.
nonisolated final class GameCubeDisc {
    let url: URL
    let file: RandomAccessFile
    var fileSize: UInt64 = 0
    var gameID: String = ""
    var gameTitle: String = ""
    var root: DiscNode!
    var fst: [FSTEntry] = []

    init(url: URL) throws {
        self.url = url
        self.file = try RandomAccessFile(forReadingFrom: url)
        self.fileSize = try file.fileSize()
        try parse()
    }

    deinit { file.close() }

    private func parse() throws {
        let header = try file.read(at: 0, count: 0x460)
        guard header.count == 0x460 else { throw WSError.ioError("Disc image too small.") }
        let gcMagic = header.be32(0x1C)
        guard gcMagic == WiiConstants.gcMagic else { throw WSError.notAWiiOrGameCubeDisc }

        gameID = header.asciiString(at: 0, length: 6)
        gameTitle = header.asciiString(at: 0x20, length: 0x40)

        let fstOffset = UInt64(header.be32(0x424))
        let fstSize = UInt64(header.be32(0x428))
        guard fstSize > 0, fstSize < 16 * 1024 * 1024 else { throw WSError.badStructure("Implausible GameCube fst.bin size.") }
        let fstData = try file.read(at: fstOffset, count: Int(fstSize))
        fst = try FSTBuilder.parse(fstData, shiftFileOffsets: false)

        root = DiscNode(name: "\(gameTitle) [\(gameID)] (GameCube)", kind: .root)
        let tree = FSTBuilder.buildTree(fst, partitionIndex: -1)
        for child in tree.children { child.parent = root }
        root.children = tree.children
    }

    func readFile(node: DiscNode) throws -> Data {
        guard node.isFile else { throw WSError.badStructure("Not a file.") }
        return try file.read(at: node.fileOffset, count: Int(node.fileSize))
    }
}
