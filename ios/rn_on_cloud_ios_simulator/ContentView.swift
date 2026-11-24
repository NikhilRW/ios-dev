import SwiftUI

struct ContentView: View {
    let name = "Nikhil Ramesh Wankhede"

    var body: some View {
        VStack(spacing: 16) {
            Text(name)
                .font(.largeTitle)

            Text("An aspiring mobile engineer")
                .foregroundStyle(.secondary)

            Text("I am learning iOS to broaden my knowledge of mobile development.")
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
    }
}

#Preview {
    ContentView()
}
