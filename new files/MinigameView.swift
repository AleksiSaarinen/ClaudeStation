import SwiftUI
import WebKit

/// SwiftUI wrapper for the Kick the Claude minigame running in a WKWebView
struct MinigameView: View {
    @ObservedObject var bridge: MinigameBridge
    @State private var isLoaded = false
    
    var body: some View {
        ZStack {
            MinigameWebView(bridge: bridge, isLoaded: $isLoaded)
            
            if !isLoaded {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading Kick the Claude...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }
}

/// NSViewRepresentable wrapping WKWebView for the minigame
struct MinigameWebView: NSViewRepresentable {
    let bridge: MinigameBridge
    @Binding var isLoaded: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isLoaded: $isLoaded, bridge: bridge)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // Transparent background
        
        // Set up bridge
        bridge.configure(webView: webView)
        
        // Load the game HTML
        if let htmlURL = Bundle.main.url(forResource: "kick-the-claude", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            // Fallback: try loading from the app's resources directory
            // During development, you might load from a local dev server instead:
            // webView.load(URLRequest(url: URL(string: "http://localhost:5173")!))
            loadInlineHTML(into: webView)
        }
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    /// Fallback: load a minimal placeholder if the HTML bundle isn't found
    private func loadInlineHTML(into webView: WKWebView) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body {
                    margin: 0; padding: 40px; background: #1a1a2e;
                    color: #e0e0e0; font-family: 'SF Mono', monospace;
                    display: flex; align-items: center; justify-content: center;
                    min-height: 100vh; text-align: center;
                }
                h1 { color: #FF6B35; font-size: 18px; }
                p { color: #666; font-size: 13px; max-width: 400px; line-height: 1.6; }
                code { background: #16213e; padding: 2px 6px; border-radius: 4px; font-size: 12px; }
            </style>
        </head>
        <body>
            <div>
                <h1>Kick the Claude</h1>
                <p>Game HTML bundle not found. Build the React app first:</p>
                <p><code>cd minigame && npm run build</code></p>
                <p>Then copy the output HTML to the app's Resources folder.</p>
            </div>
            <script>
                // Stub the event API so the bridge doesn't error
                window.claudeEvent = function(type, data) {
                    console.log('[Minigame stub]', type, data);
                };
                window.loadState = function(json) {
                    console.log('[Minigame stub] loadState', json);
                };
            </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoaded: Bool
        let bridge: MinigameBridge
        
        init(isLoaded: Binding<Bool>, bridge: MinigameBridge) {
            _isLoaded = isLoaded
            self.bridge = bridge
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.isLoaded = true
                // Load any saved game state
                self.bridge.loadSavedState()
            }
        }
    }
}
