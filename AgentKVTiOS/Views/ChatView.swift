import SwiftUI
import SwiftData
import ManagerCore

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileStore: FamilyProfileStore
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var threads: [ChatThread]
    @State private var draftedMessage = ""

    private var appSettings: IOSBackendSettings {
        IOSBackendSettings.load()
    }

    var body: some View {
        NavigationStack {
            Group {
                if let thread = threads.first {
                    ChatThreadDetailView(
                        thread: thread,
                        draftedMessage: $draftedMessage,
                        currentProfileId: profileStore.currentProfileId
                    )
                } else {
                    ContentUnavailableView(
                        "No Chat Yet",
                        systemImage: "message",
                        description: Text(
                            appSettings.isDirectOllamaConfigured
                                ? "Create a thread to chat. Replies come directly from Ollama on your network."
                                : "Create an optional assistant thread. The Mac answers after messages sync from this device."
                        )
                    )
                }
            }
            .navigationTitle("Chat")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createThreadIfNeeded()
                    } label: {
                        Label("New Chat", systemImage: "plus")
                    }
                }
            }
            .familyProfileToolbar()
        }
    }

    private func createThreadIfNeeded() {
        let thread = ChatThread(createdByProfileId: profileStore.currentProfileId)
        modelContext.insert(thread)
        try? modelContext.save()
    }
}

private struct ChatThreadDetailView: View {
    let thread: ChatThread
    @Binding var draftedMessage: String
    let currentProfileId: UUID?

    private let backendSync = IOSBackendSyncService()

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatMessage.timestamp, order: .forward) private var allMessages: [ChatMessage]
    @Query(sort: \FamilyMember.createdAt, order: .forward) private var familyMembers: [FamilyMember]

    @State private var showClearChatConfirmation = false

    private var appSettings: IOSBackendSettings {
        IOSBackendSettings.load()
    }

    private var threadMessages: [ChatMessage] {
        allMessages.filter { $0.threadId == thread.id }
    }

    private var hasPendingReply: Bool {
        threadMessages.contains {
            $0.role == "user" && (
                $0.status == ChatMessageStatus.pending.rawValue ||
                $0.status == ChatMessageStatus.processing.rawValue
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if threadMessages.isEmpty {
                ContentUnavailableView(
                    "Start A Conversation",
                    systemImage: "text.bubble",
                    description: Text(
                        appSettings.isDirectOllamaConfigured
                            ? "Messages go straight to Ollama on your network (no tools). Configure the same model as your Mac runner."
                            : "Messages sync to your Mac; the runner replies using the same tool-aware agent loop as missions."
                    )
                )
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(threadMessages, id: \.id) { message in
                            ChatMessageRow(
                                message: message,
                                senderLabel: senderLabel(for: message),
                                directOllama: appSettings.isDirectOllamaConfigured
                            )
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                        .onDelete(perform: deleteMessages)
                    }
                    .listStyle(.plain)
                    .onAppear {
                        scrollToLatest(proxy: proxy)
                    }
                    .onChange(of: threadMessages.count) { _, _ in
                        scrollToLatest(proxy: proxy)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                if hasPendingReply {
                    Label(pendingStatusText, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .bottom, spacing: 12) {
                    TextField("Message the assistant", text: $draftedMessage, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)

                    Button("Send") {
                        sendMessage()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draftedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .background(.thinMaterial)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showClearChatConfirmation = true
                } label: {
                    Label("Clear messages", systemImage: "trash")
                }
                .disabled(threadMessages.isEmpty)
            }
        }
        .confirmationDialog(
            "Remove all messages in this chat?",
            isPresented: $showClearChatConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                clearAllMessagesInThread()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. The thread stays open.")
        }
    }

    private var pendingStatusText: String {
        if appSettings.isDirectOllamaConfigured {
            return "Contacting Ollama…"
        }
        return "Waiting for the Mac runner to respond…"
    }

    private func senderLabel(for message: ChatMessage) -> String {
        if message.role != "user" { return "Agent" }
        if let id = message.authorProfileId,
           let m = familyMembers.first(where: { $0.id == id }) {
            return m.displayName
        }
        return "You"
    }

    private func scrollToLatest(proxy: ScrollViewProxy) {
        guard let lastId = threadMessages.last?.id else { return }
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(lastId, anchor: .bottom)
            }
        }
    }

    private func deleteMessages(at offsets: IndexSet) {
        let toRemove = offsets.compactMap { threadMessages.indices.contains($0) ? threadMessages[$0] : nil }
        for msg in toRemove {
            modelContext.delete(msg)
        }
        thread.updatedAt = Date()
        try? modelContext.save()
    }

    private func clearAllMessagesInThread() {
        for message in threadMessages {
            modelContext.delete(message)
        }
        thread.updatedAt = Date()
        try? modelContext.save()
    }

    private func sendMessage() {
        let trimmed = draftedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let settings = IOSBackendSettings.load()
        if settings.isDirectOllamaConfigured,
           let baseURL = settings.ollamaBaseURL,
           let model = settings.ollamaModel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !model.isEmpty {
            let message = ChatMessage(
                threadId: thread.id,
                role: "user",
                content: trimmed,
                status: ChatMessageStatus.processing.rawValue,
                authorProfileId: currentProfileId
            )
            modelContext.insert(message)
            thread.updatedAt = Date()
            try? modelContext.save()
            draftedMessage = ""
            Task {
                await completeDirectOllama(userMessage: message, baseURL: baseURL, model: model)
            }
            return
        }

        let message = ChatMessage(
            threadId: thread.id,
            role: "user",
            content: trimmed,
            status: ChatMessageStatus.pending.rawValue,
            authorProfileId: currentProfileId
        )
        modelContext.insert(message)
        thread.updatedAt = Date()
        try? modelContext.save()
        draftedMessage = ""
        Task {
            await backendSync.notifyChatWakeIfNeeded()
        }
    }

    @MainActor
    private func completeDirectOllama(userMessage: ChatMessage, baseURL: URL, model: String) async {
        let client = OllamaClient(baseURL: baseURL, model: model)
        let messages = ollamaMessagesForAPI()
        do {
            let reply = try await client.chat(messages: messages, tools: nil)
            let text = reply.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            userMessage.status = ChatMessageStatus.completed.rawValue
            userMessage.errorMessage = nil
            let assistant = ChatMessage(
                threadId: thread.id,
                role: "assistant",
                content: text.isEmpty ? "(empty reply)" : text,
                status: ChatMessageStatus.completed.rawValue
            )
            modelContext.insert(assistant)
            thread.updatedAt = Date()
            try modelContext.save()
        } catch {
            userMessage.status = ChatMessageStatus.failed.rawValue
            userMessage.errorMessage = error.localizedDescription
            thread.updatedAt = Date()
            try? modelContext.save()
        }
    }

    /// Transcript for Ollama `/api/chat` (direct path: no tool execution on iOS).
    private func ollamaMessagesForAPI() -> [OllamaClient.Message] {
        ChatOllamaTranscript.messagesForAPI(systemPrompt: thread.systemPrompt, threadMessages: threadMessages)
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage
    let senderLabel: String
    var directOllama: Bool = false

    private var isUser: Bool { message.role == "user" }

    private var bubbleColor: Color {
        if isUser {
            return .blue
        }
        if message.status == ChatMessageStatus.failed.rawValue {
            return .red
        }
        return Color(.secondarySystemBackground)
    }

    private var textColor: Color {
        isUser ? .white : .primary
    }

    private var statusCaption: String? {
        if let errorMessage = message.errorMessage, message.status == ChatMessageStatus.failed.rawValue {
            return errorMessage
        }
        if isUser && message.status == ChatMessageStatus.processing.rawValue {
            return directOllama ? "Thinking…" : "Processing"
        }
        if isUser && message.status == ChatMessageStatus.pending.rawValue {
            return "Queued"
        }
        return nil
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 6) {
                Text(message.content)
                    .foregroundStyle(textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Text(senderLabel)
                    Text(message.timestamp, style: .time)
                    if let statusCaption {
                        Text(statusCaption)
                    }
                }
                .font(.caption2)
                .foregroundStyle(isUser ? .white.opacity(0.85) : .secondary)
            }
            .padding(12)
            .background(bubbleColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .id(message.id)
            if !isUser { Spacer(minLength: 48) }
        }
    }
}
