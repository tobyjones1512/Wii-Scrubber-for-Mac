import Foundation

/// Single-file extract/replace, matching the original tool's right-click "Save"/"Replace" menu
/// items. Replace tries to write the new data into the file's existing byte range first (matching
/// or shrinking size), and falls back to relocating into free space inside the same partition's
/// already-allocated data area when the new file is bigger, exactly like the original tool's "will
/// try and relocate it to another part of the disc image that does have enough space" behaviour.
nonisolated enum FileOperations {

    static func extract(disc: WiiDisc, node: DiscNode, to destination: URL) throws {
        let data: Data
        if let compName = componentName(node) {
            data = try disc.readPartitionComponent(partitionIndex: node.partitionIndex!, name: compName)
        } else {
            data = try disc.readFile(node: node)
        }
        try data.write(to: destination, options: .atomic)
    }

    private static func componentName(_ node: DiscNode) -> String? {
        if case .partitionComponent(let name) = node.kind { return name }
        return nil
    }

    /// Replaces a file's contents in-place on the opened disc image (which must be opened for
    /// writing -- see `WiiDisc.openForWriting`). Updates the FST and, if the file moved or the
    /// partition's signed metadata was touched, fake-signs the partition's ticket/TMD.
    static func replace(discURL: URL, disc: WiiDisc, node: DiscNode, newData: Data, log: (String) -> Void) throws {
        guard node.isFile, let pIdx = node.partitionIndex else { throw WSError.badStructure("Select a file first.") }
        var p = disc.partitions[pIdx]
        let writer = try RandomAccessFile(forUpdating: discURL)
        defer { writer.close() }

        guard var entry = p.fst.first(where: { $0.index == node.fstIndex }) else {
            throw WSError.badStructure("FST entry not found.")
        }

        let oldOffset = entry.fileOffsetOrParent
        let oldSize = entry.lengthOrNextIndex
        var newOffset = oldOffset

        if UInt64(newData.count) > oldSize {
            log("New file is larger than the original (\(newData.count) vs \(oldSize) bytes) -- looking for free space in the partition...")
            guard let freeOffset = findFreeSpace(p: p, excludingFSTIndex: entry.index, neededSize: UInt64(newData.count)) else {
                throw WSError.ioError("""
                Not enough free space left in this partition to relocate "\(node.name)". \
                Use Partition > Resize/Shrink to make room first, exactly as the original tool required.
                """)
            }
            newOffset = freeOffset
            log("Relocating \"\(node.name)\" to offset 0x\(String(newOffset, radix: 16)).")
        }

        log("Writing \(newData.count) bytes...")
        try ClusterCrypto.write(file: writer, partitionDataOffset: p.header.dataOffset, titleKey: p.titleKey,
                                 streamOffset: newOffset, data: newData)

        entry.fileOffsetOrParent = newOffset
        entry.lengthOrNextIndex = UInt64(newData.count)
        if let i = p.fst.firstIndex(where: { $0.index == entry.index }) { p.fst[i] = entry }

        try rewriteFST(p: &p, writer: writer, log: log)
        try TruchaOps.signPartition(&p, writer: writer)
        disc.partitions[pIdx] = p

        node.fileOffset = newOffset
        node.fileSize = UInt64(newData.count)
        log("Replace complete.")
    }

    /// Finds a byte-range inside the partition's already-allocated `[0, dataSize)` region that
    /// isn't used by any other file (or by boot.bin/apploader/fst.bin/main.dol), big enough to
    /// hold `neededSize` bytes.
    static func findFreeSpace(p: RuntimePartition, excludingFSTIndex: Int?, neededSize: UInt64) -> UInt64? {
        var used: [(UInt64, UInt64)] = [(0, systemAreaEnd(p))]
        for e in p.fst where !e.isDirectory && e.index != excludingFSTIndex {
            used.append((e.fileOffsetOrParent, e.fileOffsetOrParent + e.lengthOrNextIndex))
        }
        used.sort { $0.0 < $1.0 }

        var cursor: UInt64 = 0
        for (start, end) in used {
            if start > cursor, start - cursor >= neededSize { return cursor }
            cursor = max(cursor, end)
        }
        if p.header.dataSize > cursor, p.header.dataSize - cursor >= neededSize { return cursor }
        return nil
    }

    /// boot.bin + bi2.bin + apploader.img + main.dol + fst.bin region is never free space.
    /// apploader/dol have no FST entries of their own, so the only precisely-known lower bound
    /// for "everything system-related" is fst.bin's own end -- which, on every standard disc
    /// layout, comes after both of them.
    static func systemAreaEnd(_ p: RuntimePartition) -> UInt64 {
        max(p.fstOffset + p.fstSize, 0x2440)
    }

    static func rewriteFST(p: inout RuntimePartition, writer: RandomAccessFile, log: (String) -> Void) throws {
        let newFST = FSTBuilder.serialize(p.fst)
        var targetOffset = p.fstOffset

        if UInt64(newFST.count) > max(p.maxFSTSize, p.fstSize) {
            log("fst.bin grew beyond its original reserved size; relocating it into free space too.")
            guard let freeOffset = findFreeSpace(p: p, excludingFSTIndex: nil, neededSize: UInt64(newFST.count)) else {
                throw WSError.ioError("Not enough free space to relocate the growing fst.bin.")
            }
            targetOffset = freeOffset
            let bootBin = try ClusterCrypto.read(file: writer, partitionDataOffset: p.header.dataOffset,
                                                  titleKey: p.titleKey, streamOffset: 0, length: 0x480)
            var newBoot = bootBin
            let w = MutableDataWriter(); w.putU32Shifted(targetOffset)
            newBoot.replaceSubrange(0x424..<0x428, with: w.data)
            let w2 = MutableDataWriter(); w2.putU32Shifted(UInt64(newFST.count))
            newBoot.replaceSubrange(0x42C..<0x430, with: w2.data)
            try ClusterCrypto.write(file: writer, partitionDataOffset: p.header.dataOffset, titleKey: p.titleKey,
                                     streamOffset: 0, data: newBoot.subdata(at: 0, length: 0x480))
            p.maxFSTSize = UInt64(newFST.count)
        }
        try ClusterCrypto.write(file: writer, partitionDataOffset: p.header.dataOffset, titleKey: p.titleKey,
                                 streamOffset: targetOffset, data: newFST)
        p.fstOffset = targetOffset
        p.fstSize = UInt64(newFST.count)
    }
}

/// Fake-signs a partition's ticket and TMD after its data/FST has been modified, using the
/// well-documented "Trucha bug" padding offsets (see `WiiCrypto.truchaSign`), and writes the
/// updated ticket/TMD bytes back to the disc image.
nonisolated enum TruchaOps {
    static func signPartition(_ p: inout RuntimePartition, writer: RandomAccessFile) throws {
        var ticket = p.ticketData
        WiiCrypto.truchaSign(&ticket, signedRange: 0x140..<Int(WiiConstants.ticketSize), paddingOffset: 0x262)
        try writer.write(ticket, at: p.entry.offset)
        p.ticketData = ticket

        var tmd = p.tmdData
        let tmdSignedEnd = tmd.count
        WiiCrypto.truchaSign(&tmd, signedRange: 0x140..<tmdSignedEnd, paddingOffset: 0x1E2)
        try writer.write(tmd, at: p.header.tmdOffset)
        p.tmdData = tmd
    }
}
