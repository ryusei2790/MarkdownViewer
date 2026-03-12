import SwiftUI
import MarkdownUI

struct ContentView: View {
    @State private var markdownContent: String = "Drag and drop a **Markdown** file here."
    @State private var isTargeted = false

    var body: some View {
        ZStack {
            // Dark mode background
            Color.black.edgesIgnoringSafeArea(.all)
            
            ScrollView {
                Markdown(markdownContent)
                    .markdownTheme(.gitHub) // You can customize styling here
                    .padding(.vertical, 40)
                    .padding(.horizontal, 32) // ~2rem
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Overlay for Drope Zone feedback
            if isTargeted {
                Color.blue.opacity(0.2)
                    .border(Color.blue, width: 2)
                    .edgesIgnoringSafeArea(.all)
            }
        }
        .preferredColorScheme(.dark)
        // Set window size
        .frame(minWidth: 400, idealWidth: 600, minHeight: 400, idealHeight: 600)
        // Drag and drop support
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") }) else { return false }
            
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      let content = try? String(contentsOf: url) else {
                    return
                }
                
                DispatchQueue.main.async {
                    self.markdownContent = content
                }
            }
            return true
        }
    }
}

@main
struct MarkdownViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
