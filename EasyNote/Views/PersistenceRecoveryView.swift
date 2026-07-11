import SwiftUI

struct PersistenceRootView: View {
    @ObservedObject var bootstrap: PersistenceBootstrap

    var body: some View {
        Group {
            switch bootstrap.state {
            case .loading:
                ProgressView("正在打开本地数据...")
            case .ready(let container):
                ContentView()
                    .modelContainer(container)
            case .failed(let failure):
                PersistenceRecoveryView(
                    failure: failure,
                    canRebuild: bootstrap.canCreateRecoveryCopy,
                    retry: bootstrap.retry,
                    rebuild: bootstrap.createRecoveryCopyAndRebuild
                )
            }
        }
        .task {
            bootstrap.loadIfNeeded()
        }
    }
}

private struct PersistenceRecoveryView: View {
    let failure: PersistenceBootstrapFailure
    let canRebuild: Bool
    let retry: () -> Void
    let rebuild: () -> Void

    @State private var isShowingRebuildConfirmation = false

    var body: some View {
        ContentUnavailableView {
            Label("无法打开本地数据", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            VStack(spacing: 8) {
                Text(failure.message)
                if let recoveryURL = failure.recoveryURL {
                    Text("恢复副本：\(recoveryURL.path)")
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }
        } actions: {
            VStack(spacing: 12) {
                Button(action: retry) {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)

                if canRebuild {
                    Button(role: .destructive) {
                        isShowingRebuildConfirmation = true
                    } label: {
                        Label("创建恢复副本并重建", systemImage: "externaldrive.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .alert("确认重建本地数据库？", isPresented: $isShowingRebuildConfirmation) {
            Button("取消", role: .cancel) {}
            Button("创建副本并重建", role: .destructive, action: rebuild)
        } message: {
            Text("EasyNote 会先把现有数据库及其 WAL/SHM 文件复制到 Documents/EasyNoteRecovery，然后才移除原文件并创建新数据库。")
        }
    }
}
