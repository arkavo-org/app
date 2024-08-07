import SwiftUI

struct PerformanceInfoOverlay: View {
    let nanoTime: TimeInterval
    let nanoCitiesCount: Int
    let citiesCount: Int
    let decryptTime: TimeInterval
    let decryptCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("nanoTDF info")
                .font(.headline)
                .padding(.bottom, 4)
            InfoRow(label: "bplist count", value: "\(citiesCount)")
            InfoRow(label: "Encrypt time", value: String(format: "%.2f s", nanoTime))
            InfoRow(label: "Nano count", value: "\(nanoCitiesCount)")
            InfoRow(label: "Roundtrip time", value: String(format: "%.2f s", decryptTime))
            InfoRow(label: "Decrypt count", value: "\(decryptCount)")
        }
        .padding()
        .background(Color.black.opacity(0.7))
        .cornerRadius(10)
        .foregroundColor(.white)
        .frame(width: 220)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

struct PerformanceInfoOverlay_Previews: PreviewProvider {
    static var previews: some View {
        PerformanceInfoOverlay(
            nanoTime: 0.02,
            nanoCitiesCount: 62,
            citiesCount: 62,
            decryptTime: 0.07,
            decryptCount: 0
        )
        .previewLayout(.sizeThatFits)
        .padding()
        .background(Color.blue) // To see the overlay clearly in preview
    }
}
