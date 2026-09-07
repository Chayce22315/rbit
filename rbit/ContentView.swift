import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 56))
                    .symbolRenderingMode(.hierarchical)

                Text("rbit")
                    .font(.largeTitle.bold())

                Text("ios 27 sideloading, built around local device communication")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Button {
                    // ipa importing will be implemented in a later milestone.
                } label: {
                    Label("add ipa", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("rbit")
        }
    }
}

#Preview {
    ContentView()
}
