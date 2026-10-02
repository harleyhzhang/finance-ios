import SwiftUI

@main struct FinanceApp: App {
    @StateObject private var store = SnapshotStore()
    var body: some Scene { WindowGroup { RootView().environmentObject(store).preferredColorScheme(.dark) } }
}

struct RootView: View {
    @EnvironmentObject var store: SnapshotStore

    var body: some View {
        content
            .task {
                // An explicit local operator command; ordinary launches stay offline.
                if ProcessInfo.processInfo.arguments.contains("--refresh-snapshot") { await store.refresh() }
            }
            .onOpenURL { url in
                do { try store.importConnection(url) }
                catch { store.message = "This connection file couldn't be installed." }
            }
            .alert("Finance", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
                Button("OK") { store.message = nil }
            } message: { Text(store.message ?? "") }
    }

    @ViewBuilder private var content: some View {
        if let snapshot = store.snapshot {
            DashboardView(snapshot: snapshot)
        } else {
            ScrollView {
                ContentUnavailableView("Your net worth", systemImage: "chart.xyaxis.line",
                    description: Text("Open your connection file, then pull to load your saved snapshot."))
                    .padding(.top, 100)
            }
            .background(Theme.background)
            .refreshable { await store.refresh() }
            .scrollBounceBehavior(.always, axes: .vertical)
        }
    }
}
