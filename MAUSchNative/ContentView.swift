import SwiftUI
import WebKit

private let mauschURL = URL(string: "https://ppt0320.github.io/mausch/")!

struct ContentView: View {
    var body: some View {
        WebAppView()
            .ignoresSafeArea(edges: .bottom)
            .background(Color(red: 11/255, green: 18/255, blue: 32/255))
    }
}

#if os(iOS)
struct WebAppView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 11/255, green: 18/255, blue: 32/255, alpha: 1)
        view.scrollView.backgroundColor = view.backgroundColor
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: mauschURL, cachePolicy: .useProtocolCachePolicy))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#elseif os(macOS)
struct WebAppView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.load(URLRequest(url: mauschURL, cachePolicy: .useProtocolCachePolicy))
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
