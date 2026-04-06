import SwiftUI

struct ChatView: View {
    @Environment(ChatStore.self) private var chatStore
    @EnvironmentObject private var profileStore: FamilyProfileStore

    @State private var path: [UUID] = []
    @State private var creationErrorMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(chatStore.threads, id: \.id) { thread in
                    NavigationLink(value: thread.id) {
                        ChatThreadRow(thread: thread)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Chat")
            .navigationDestination(for: UUID.self) { threadID in
                ChatThreadDetailView(threadID: threadID)
            }
            .refreshable {
                await chatStore.refreshThreads()
            }
            .overlay {
                if chatStore.isLoadingThreads && chatStore.threads.isEmpty {
                    ProgressView("Loading chats…")
                } else if chatStore.threads.isEmpty {
                    ContentUnavailableView(
                        "No Chat Yet",
                        systemImage: "message",
                        description: Text("Create a thread to message the family assistant through the server-backed chat queue.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await createThread() }
                    } label: {
                        Label("New Chat", systemImage: "plus")
                    }
                }
            }
            .familyProfileToolbar()
        }
        .task {
            await chatStore.refreshThreads()
        }
        .alert("Could Not Create Chat", isPresented: Binding(
            get: { creationErrorMessage != nil },
            set: { if !$0 { creationErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { creationErrorMessage = nil }
        } message: {
            Text(creationErrorMessage ?? "The chat thread could not be created.")
        }
    }

    @MainActor
    private func createThread() async {
        do {
            let thread = try await chatStore.createThread(createdByProfileId: profileStore.currentProfileId)
            path = [thread.id]
            await chatStore.refreshThread(id: thread.id)
        } catch {
            creationErrorMessage = error.localizedDescription
            IOSRuntimeLog.log("[ChatView] Thread creation failed: \(error)")
        }
    }
}

private struct ChatThreadRow: View {
    let thread: IOSBackendChatThread

    private var subtitle: String {
        if let preview = thread.latestMessagePreview?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preview.isEmpty {
            return preview
        }
        return "No messages yet"
    }

    private var statusLabel: String? {
        guard thread.pendingMessageCount > 0 else { return nil }
        if thread.pendingMessageCount == 1 {
            return "1 pending"
        }
        return "\(thread.pendingMessageCount) pending"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "message")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(thread.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    if let statusLabel {
                        Text(statusLabel)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    if let latestMessageAt = thread.latestMessageAt {
                        Text(latestMessageAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ChatThreadDetailView: View {
    let threadID: UUID

    @Environment(ChatStore.self) private var chatStore
    @Environment(FamilyMembersStore.self) private var familyMembersStore
    @EnvironmentObject private var profileStore: FamilyProfileStore

    @State private var draftedMessage = ""
    @State private var sendErrorMessage: String?

    private var thread: IOSBackendChatThread? {
        chatStore.thread(for: threadID)
    }

    private var messages: [IOSBackendChatMessage] {
        chatStore.messages(for: threadID)
    }

    private var pendingBannerTitle: String {
        "Waiting for the Mac agent to respond…"
    }

    private var pendingBannerDetail: String {
        "Keep AgentKVT Mac running with the same API URL and agent token as your family server. Without that, chat stays queued."
    }

    private var messageIDs: [UUID] {
        messages.map(\.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                ContentUnavailableView(
                    "Start A Conversation",
                    systemImage: "text.bubble",
                    description: Text("Messages go to the family server and the Mac runner replies through the shared Postgres-backed chat queue.")
                )
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(messages, id: \.id) { message in
                            ChatMessageRow(
                                message: message,
                                senderLabel: senderLabel(for: message)
                            )
                            .id(message.id)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .onAppear {
                        scrollToLatest(proxy: proxy)
                    }
                    .onChange(of: messageIDs) { _, _ in
                        scrollToLatest(proxy: proxy)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if chatStore.hasPendingMessages(threadId: threadID) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(pendingBannerTitle, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(pendingBannerDetail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Message the assistant", text: $draftedMessage, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)

                    Button("Send") {
                        Task { await sendMessage() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        draftedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        chatStore.sendingThreadIDs.contains(threadID)
                    )
                }
            }
            .padding()
            .background(.thinMaterial)
        }
        .navigationTitle(thread?.title ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await chatStore.refreshThread(id: threadID)
        }
        .task {
            await chatStore.refreshThread(id: threadID)
        }
        .alert("Could Not Send Message", isPresented: Binding(
            get: { sendErrorMessage != nil },
            set: { if !$0 { sendErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { sendErrorMessage = nil }
        } message: {
            Text(sendErrorMessage ?? "The message could not be queued.")
        }
    }

    private func senderLabel(for message: IOSBackendChatMessage) -> String {
        if message.role != "user" { return "Agent" }
        if let id = message.authorProfileId,
           let member = familyMembersStore.members.first(where: { $0.id == id }) {
            return member.displayName
        }
        return "You"
    }

    private func scrollToLatest(proxy: ScrollViewProxy) {
        guard let lastID = messages.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
    }

    @MainActor
    private func sendMessage() async {
        do {
            try await chatStore.sendMessage(
                threadId: threadID,
                content: draftedMessage,
                authorProfileId: profileStore.currentProfileId
            )
            draftedMessage = ""
        } catch {
            sendErrorMessage = error.localizedDescription
            IOSRuntimeLog.log("[ChatThreadDetailView] Send failed for \(threadID): \(error)")
        }
    }
}

private struct ChatMessageRow: View {
    let message: IOSBackendChatMessage
    let senderLabel: String

    private var isUser: Bool {
        message.role == "user"
    }

    private var bubbleColor: Color {
        if isUser {
            return .blue
        }
        if message.status == "failed" {
            return .red
        }
        return Color(.secondarySystemBackground)
    }

    private var textColor: Color {
        isUser ? .white : .primary
    }

    private var statusCaption: String? {
        if let errorMessage = message.errorMessage,
           message.status == "failed" {
            return errorMessage
        }
        if isUser && message.status == "processing" {
            return "Processing"
        }
        if isUser && message.status == "pending" {
            return "Queued"
        }
        return nil
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 28) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(senderLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(message.content)
                    .foregroundStyle(textColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleColor)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .textSelection(.enabled)

                if let statusCaption {
                    Text(statusCaption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if !isUser { Spacer(minLength: 28) }
        }
    }
}
