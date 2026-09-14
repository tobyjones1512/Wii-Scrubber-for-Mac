import Foundation

/// Reads/writes the "de-hashed" 0x7C00-byte-per-cluster decrypted data stream that partition data
/// offsets (boot.bin, fst.bin, FST file offsets, ...) are expressed in.
///
/// Wii partition data is stored as consecutive 0x8000-byte clusters, each made of a 0x400-byte
/// encrypted hash block followed by 0x7C00 bytes of encrypted content. The content of a cluster is
/// decrypted with the partition's title key using, as IV, the *still-encrypted* bytes at offset
/// 0x3D0 within that same cluster's hash block (a well known quirk of the format -- no need to
/// decrypt the hash block first to get it).
nonisolated enum ClusterCrypto {

    /// Read `length` bytes starting at `streamOffset` (offset into the de-hashed stream) from a
    /// partition's data area, decrypting as needed.
    static func read(file: RandomAccessFile, partitionDataOffset: UInt64, titleKey: [UInt8],
                      streamOffset: UInt64, length: UInt64) throws -> Data {
        guard length > 0 else { return Data() }
        var result = Data(capacity: Int(length))
        var remaining = length
        var pos = streamOffset

        while remaining > 0 {
            let clusterIndex = pos / WiiConstants.dataPerCluster
            let intraOffset = pos % WiiConstants.dataPerCluster
            let clusterFileOffset = partitionDataOffset + clusterIndex * WiiConstants.clusterSize
            let raw = try file.read(at: clusterFileOffset, count: Int(WiiConstants.clusterSize))
            guard raw.count == Int(WiiConstants.clusterSize) else {
                throw WSError.ioError("Unexpected EOF reading cluster \(clusterIndex).")
            }
            let iv = [UInt8](raw.subdata(at: 0x3D0, length: 16))
            let cipherData = raw.subdata(at: Int(WiiConstants.hashBlockSize), length: Int(WiiConstants.dataPerCluster))
            let plain = WiiCrypto.aesDecrypt(key: titleKey, iv: iv, data: cipherData)

            let take = min(remaining, WiiConstants.dataPerCluster - intraOffset)
            result.append(plain.subdata(at: Int(intraOffset), length: Int(take)))
            remaining -= take
            pos += take
        }
        return result
    }

    /// Write `data` at `streamOffset` into a partition's data area. The 0x400-byte hash block of
    /// every touched cluster is left byte-for-byte as it already was on disk (WiiScrubber-style
    /// tools never recompute the H0-H3 hash tree; they instead rely on `WiiCrypto.truchaSign` so
    /// IOS skips verifying it), which conveniently also means the per-cluster IV does not change.
    static func write(file: RandomAccessFile, partitionDataOffset: UInt64, titleKey: [UInt8],
                       streamOffset: UInt64, data: Data) throws {
        guard !data.isEmpty else { return }
        var remaining = data.count
        var srcOffset = 0
        var pos = streamOffset

        while remaining > 0 {
            let clusterIndex = pos / WiiConstants.dataPerCluster
            let intraOffset = Int(pos % WiiConstants.dataPerCluster)
            let clusterFileOffset = partitionDataOffset + clusterIndex * WiiConstants.clusterSize

            var raw = try file.read(at: clusterFileOffset, count: Int(WiiConstants.clusterSize))
            if raw.count != Int(WiiConstants.clusterSize) {
                raw = Data(repeating: 0, count: Int(WiiConstants.clusterSize))
            }
            let iv = [UInt8](raw.subdata(at: 0x3D0, length: 16))
            var cipherData = raw.subdata(at: Int(WiiConstants.hashBlockSize), length: Int(WiiConstants.dataPerCluster))
            var plain = WiiCrypto.aesDecrypt(key: titleKey, iv: iv, data: cipherData)

            let take = min(remaining, Int(WiiConstants.dataPerCluster) - intraOffset)
            plain.replaceSubrange(intraOffset..<(intraOffset + take), with: data.subdata(at: srcOffset, length: take))

            cipherData = WiiCrypto.aesEncrypt(key: titleKey, iv: iv, data: plain)
            raw.replaceSubrange(Int(WiiConstants.hashBlockSize)..<Int(WiiConstants.clusterSize), with: cipherData)
            try file.write(raw, at: clusterFileOffset)

            remaining -= take
            srcOffset += take
            pos += UInt64(take)
        }
    }

    /// Number of whole+partial clusters spanned by a partition data region of `dataSize` bytes.
    static func clusterCount(forDataSize dataSize: UInt64) -> UInt64 {
        (dataSize + WiiConstants.dataPerCluster - 1) / WiiConstants.dataPerCluster
    }
}
