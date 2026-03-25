import SwiftUI
import SwiftData
import ManagerCore

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var profileStore: FamilyProfileStore
    @Query(sort: \ChatThread.updatedAt, order: .reverse) private var threads: [ChatThread]
    @State private var draftedMessage = ""

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
                        description: Text("Create an optional assistant thread. The Mac runner will answer when it next syncs.")
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

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatMessage.timestamp, order: .forward) private var allMessages: [ChatMessage]
    @Query(sort: \FamilyMember.createdAt, order: .forward) private var familyMembers: [FamilyMember]

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
                    description: Text("Messages are stored locally and answered by the Mac runner using the same tool-aware agent loop as missions.")
                )
            } else {
                ScrollViewReader { proxy in
                    List(threadMessages, id: \.id) { message in
                        ChatMessageRow(message: message, senderLabel: senderLabel(for: message))
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
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
                    Label("Waiting for the Mac runner to respond…", systemImage: "clock")
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

    private func sendMessage() {
        let trimmed = draftedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
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
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage
    let senderLabel: String

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
                    if let errorMessage = message.errorMessage, message.status == ChatMessageStatus.failed.rawValue {
                        Text(errorMessage)
                    } else if isUser && message.status == ChatMessageStatus.processing.rawValue {
                        Text("Processing")
                    } else if isUser && message.status == ChatMessageStatus.pending.rawValue {
                        Text("Queued")
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
