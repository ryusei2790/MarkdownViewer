import SwiftUI
import MarkdownUI

/// ファイルツリーのノードを表す再帰的なデータモデル
/// フォルダとファイルの両方を表現し、ツリー構造を構築する
struct FileNode: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]

    /// URLからFileNodeを生成する（ディレクトリの場合は子ノードも再帰的に構築）
    static func buildTree(from url: URL, allowedExtensions: Set<String>) -> FileNode? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }

        if isDir.boolValue {
            // ディレクトリ: 子要素を再帰的に構築
            let contents = (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            let childNodes = contents
                .compactMap { buildTree(from: $0, allowedExtensions: allowedExtensions) }
                .sorted { lhs, rhs in
                    // フォルダを先に、次にファイルをアルファベット順で表示
                    if lhs.isDirectory != rhs.isDirectory {
                        return lhs.isDirectory
                    }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }

            // .mdファイルを含まないフォルダは除外
            guard !childNodes.isEmpty else { return nil }

            return FileNode(name: url.lastPathComponent, url: url, isDirectory: true, children: childNodes)
        } else {
            // ファイル: 許可された拡張子のみ
            let ext = url.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { return nil }
            return FileNode(name: url.lastPathComponent, url: url, isDirectory: false, children: [])
        }
    }

    /// ツリー内の全ファイル（ディレクトリ以外）をフラットなリストとして返す
    func allFiles() -> [URL] {
        if !isDirectory {
            return [url]
        }
        return children.flatMap { $0.allFiles() }
    }
}

/// サイドバーのファイルツリー行を表示するビュー
struct FileTreeRow: View {
    let node: FileNode
    let selectedURL: URL?
    let onSelect: (URL) -> Void

    var body: some View {
        if node.isDirectory {
            // フォルダ: 展開/折りたたみ可能なDisclosureGroup
            DisclosureGroup {
                ForEach(node.children) { child in
                    FileTreeRow(node: child, selectedURL: selectedURL, onSelect: onSelect)
                }
            } label: {
                Label(node.name, systemImage: "folder.fill")
                    .foregroundColor(.secondary)
            }
        } else {
            // ファイル: クリックでプレビュー切り替え
            Button {
                onSelect(node.url)
            } label: {
                Label(node.name, systemImage: "doc.text")
                    .foregroundColor(node.url == selectedURL ? .accentColor : .primary)
                    .fontWeight(node.url == selectedURL ? .bold : .regular)
            }
            .buttonStyle(.plain)
        }
    }
}

/// 初期画面のドロップゾーンを表示するビュー
struct DropZonePlaceholder: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Markdownファイルをドラッグ&ドロップ")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            Text("ファイルまたはフォルダをドロップしてプレビュー")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(["md", "markdown"], id: \.self) { ext in
                    Text(".\(ext)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ContentView: View {
    @State private var markdownContent: String? = nil
    @State private var isTargeted = false
    @State private var showError = false
    @State private var errorMessage = ""
    /// フォルダドロップ時に検出されたMarkdownファイルのURL一覧
    @State private var markdownFiles: [URL] = []
    /// 現在表示中のファイルのURL
    @State private var selectedFileURL: URL? = nil
    /// サイドバー用のファイルツリー（フォルダドロップ時のみ構築）
    @State private var fileTree: FileNode? = nil
    /// サイドバーの表示/非表示
    @State private var showSidebar = false

    /// Markdownファイルとして許可する拡張子
    private let allowedExtensions: Set<String> = ["md", "markdown"]

    /// ウィンドウタイトルに表示するテキスト
    private var windowTitle: String {
        if let url = selectedFileURL {
            return url.lastPathComponent
        }
        return "Markdown Viewer"
    }

    var body: some View {
        NavigationSplitView {
            // サイドバー: ファイルツリー
            if let tree = fileTree, showSidebar {
                List {
                    ForEach(tree.children) { node in
                        FileTreeRow(node: node, selectedURL: selectedFileURL) { url in
                            loadFile(url: url)
                        }
                    }
                }
                .listStyle(.sidebar)
                .navigationTitle(tree.name)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "folder")
                        .font(.title)
                        .foregroundColor(.secondary)
                    Text("フォルダをドロップすると\nファイルツリーが表示されます")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } detail: {
            // メインエリア: Markdownプレビュー or 初期画面
            ZStack {
                if let content = markdownContent {
                    // Markdownプレビュー表示
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // ファイル名ヘッダー
                            if let url = selectedFileURL {
                                HStack {
                                    Image(systemName: "doc.text")
                                        .foregroundColor(.secondary)
                                    Text(url.lastPathComponent)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(.horizontal, 32)
                                .padding(.top, 20)
                                .padding(.bottom, 8)

                                Divider()
                                    .padding(.horizontal, 32)
                            }

                            Markdown(content)
                                .markdownTheme(.gitHub)
                                .padding(.vertical, 24)
                                .padding(.horizontal, 32)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    // 初期画面: ドロップゾーンのプレースホルダー
                    DropZonePlaceholder()
                }

                // ドラッグ中のオーバーレイフィードバック
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                        .background(Color.accentColor.opacity(0.08))
                        .padding(8)
                        .animation(.easeInOut(duration: 0.2), value: isTargeted)
                }
            }
        }
        .navigationTitle(windowTitle)
        .frame(minWidth: 600, idealWidth: 900, minHeight: 400, idealHeight: 600)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier("public.file-url") }) else { return false }

            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    DispatchQueue.main.async {
                        self.showError(message: "ファイルの読み込みに失敗しました。")
                    }
                    return
                }

                // ディレクトリかファイルかを判定して処理を分岐
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
                    DispatchQueue.main.async {
                        self.showError(message: "指定されたパスが存在しません。")
                    }
                    return
                }

                if isDir.boolValue {
                    // フォルダ: ファイルツリーを構築して最初のファイルを表示
                    let tree = FileNode.buildTree(from: url, allowedExtensions: self.allowedExtensions)
                    let files = tree?.allFiles() ?? []

                    guard let tree = tree, !files.isEmpty else {
                        DispatchQueue.main.async {
                            self.showError(message: "フォルダ内にMarkdownファイルが見つかりませんでした。\n対応形式: .md, .markdown")
                        }
                        return
                    }

                    do {
                        let content = try String(contentsOf: files[0], encoding: .utf8)
                        DispatchQueue.main.async {
                            self.fileTree = tree
                            self.markdownFiles = files
                            self.selectedFileURL = files[0]
                            self.markdownContent = content
                            self.showSidebar = true
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.showError(message: "ファイルの読み込みに失敗しました。\n\(error.localizedDescription)")
                        }
                    }
                } else {
                    // 単一ファイル: 拡張子チェックして読み込み
                    let ext = url.pathExtension.lowercased()
                    guard self.allowedExtensions.contains(ext) else {
                        DispatchQueue.main.async {
                            self.showError(message: "「.\(ext)」ファイルには対応していません。\n対応形式: .md, .markdown")
                        }
                        return
                    }

                    do {
                        let content = try String(contentsOf: url, encoding: .utf8)
                        DispatchQueue.main.async {
                            self.fileTree = nil
                            self.markdownFiles = [url]
                            self.selectedFileURL = url
                            self.markdownContent = content
                            self.showSidebar = false
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.showError(message: "ファイルの読み込みに失敗しました。\n\(error.localizedDescription)")
                        }
                    }
                }
            }
            return true
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    /// 指定URLのMarkdownファイルを読み込んでプレビューに表示する
    private func loadFile(url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            self.selectedFileURL = url
            self.markdownContent = content
        } catch {
            self.showError(message: "ファイルの読み込みに失敗しました。\n\(error.localizedDescription)")
        }
    }

    /// エラーメッセージを設定してアラートを表示する
    private func showError(message: String) {
        errorMessage = message
        showError = true
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
