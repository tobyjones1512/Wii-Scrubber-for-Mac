import SwiftUI

/// File > Load Keys. Matches the original tool's requirement of a user-supplied key.bin
/// (+ optional kkey.bin for Korean discs) sitting next to the ISO -- nothing embedded here.
struct KeysView: View {
    @ObservedObject var keyManager = KeyManager.shared
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Encryption Keys").font(.title2.bold())
            Text("Wii discs are AES-encrypted. Like the original tool, this app needs your own key.bin (16 bytes) to decrypt them -- nothing is embedded or downloaded. Once chosen, a key is remembered for next time you open the app.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            keyRow(label: "key.bin (common key)", path: keyManager.commonKeyPath, choose: {
                PanelPresenter.openFile { url in
                    guard let url else { return }
                    try? keyManager.loadCommonKey(from: url)
                }
            }, forget: { keyManager.forgetCommonKey() })

            keyRow(label: "kkey.bin (Korean key, optional)", path: keyManager.koreanKeyPath, choose: {
                PanelPresenter.openFile { url in
                    guard let url else { return }
                    try? keyManager.loadKoreanKey(from: url)
                }
            }, forget: { keyManager.forgetKoreanKey() })

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    @ViewBuilder
    private func keyRow(label: String, path: String?, choose: @escaping () -> Void, forget: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: path != nil ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(path != nil ? .green : .secondary)
            VStack(alignment: .leading) {
                Text(label)
                Text(path ?? "Not loaded").font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if path != nil {
                Button("Forget", role: .destructive, action: forget)
            }
            Button("Choose...", action: choose)
        }
    }
}
