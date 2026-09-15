import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Revolution Disk Scrubber").font(.title.bold())
            Text("A native macOS rebuild of the 2009-era Windows tool \"Wiiscrubber 1.40\" by Dack, covering the same feature set: browse/extract/replace files inside a Wii disc image, scrub padding for compression (0xFF / TRUCHA), unscrub via a diff file, trim, and partition management (delete/resize/shrink/shuffle/import/export), plus GameCube read-only browsing.")
                .fixedSize(horizontal: false, vertical: true)
            Text("This is an independent reimplementation from public documentation and the original tool's own README/FAQ -- no original source code was available to build from.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("You supply your own key.bin (and optional kkey.bin for Korean discs); nothing is embedded or downloaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 460)
    }
}
