//
//  CoachView.swift
//  HealthOS
//
//  Created by Codex on 1/20/26.
//

import PhotosUI
import SwiftUI

struct CoachView: View {
    @State private var messageText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var showSettings: Bool = false
    @State private var pendingAttachments: [ChatAttachment] = []
    @State private var selectedPhotoItem: PhotosPickerItem? = nil

    private let coaches: [CoachProfile] = [
        CoachProfile(id: CoachProfile.runningId, name: "Running Coach", subtitle: "Pacing, intervals, form", systemImage: "figure.run"),
        CoachProfile(id: CoachProfile.dietId, name: "Dietician", subtitle: "Nutrition + recovery", systemImage: "fork.knife"),
        CoachProfile(id: CoachProfile.therapyId, name: "Fitness Therapist", subtitle: "Habits, mindset, burnout", systemImage: "sparkles")
    ]

    @State private var selectedCoachId: UUID = CoachProfile.runningId
    @State private var threads: [ChatThread] = ChatThread.sampleThreads
    @State private var messagesByThread: [UUID: [ChatMessage]] = ChatMessage.sampleMessagesByThread
    @State private var selectedThreadId: UUID = ChatThread.sampleThreadId

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                headerSection
                activePlansSection
                coachPicker
                threadPicker
                Divider()
                messageList
            }
            .navigationTitle("Coach")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            CoachSettingsView()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Coaching Studio")
                .font(.title2)
                .bold()
            Text("Pick a coach and keep threads for different goals.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var activePlansSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Plans")
                .font(.headline)
            Text("No plans yet. Coaches will drop weekly plans here.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var coachPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(coaches) { coach in
                    CoachChip(
                        coach: coach,
                        isSelected: coach.id == selectedCoachId
                    ) {
                        selectedCoachId = coach.id
                        selectFirstThreadIfNeeded()
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    private var threadPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(filteredThreads) { thread in
                    ThreadChip(
                        title: thread.title,
                        isSelected: thread.id == selectedThreadId
                    ) {
                        selectedThreadId = thread.id
                    }
                }

                Button {
                    createThread()
                } label: {
                    Image(systemName: "plus")
                        .font(.subheadline)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
        .padding(.bottom, 12)
    }

    private var messageList: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(messagesForSelectedThread) { message in
                            ChatBubble(message: message, maxWidth: geo.size.width * 0.72)
                                .id(message.id)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    isInputFocused = false
                }
                .onChange(of: messagesForSelectedThread.count) {
                    if let last = messagesForSelectedThread.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    inputBar
                }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAttachments) { attachment in
                            AttachmentChip(attachment: attachment) {
                                removeAttachment(attachment)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Image(systemName: "paperclip")
                        .font(.title2)
                        .frame(width: 36, height: 36)
                }
                .onChange(of: selectedPhotoItem) {
                    if selectedPhotoItem != nil {
                        pendingAttachments.append(ChatAttachment(kind: .photo, name: "Photo"))
                        selectedPhotoItem = nil
                    }
                }

                TextField("Message your coach", text: $messageText, axis: .vertical)
                    .focused($isInputFocused)
                    .lineLimit(1...4)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .onSubmit {
                        sendMessage()
                    }

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                }
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachments.isEmpty)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }

    private var filteredThreads: [ChatThread] {
        threads.filter { $0.coachId == selectedCoachId }
    }

    private var messagesForSelectedThread: [ChatMessage] {
        messagesByThread[selectedThreadId] ?? []
    }

    private func selectFirstThreadIfNeeded() {
        if let first = filteredThreads.first {
            selectedThreadId = first.id
        } else {
            createThread()
        }
    }

    private func createThread() {
        let newThread = ChatThread(
            id: UUID(),
            title: "New thread",
            coachId: selectedCoachId
        )
        threads.insert(newThread, at: 0)
        messagesByThread[newThread.id] = [
            ChatMessage(role: .assistant, text: "What do you want to focus on today?", attachments: [])
        ]
        selectedThreadId = newThread.id
    }

    private func sendMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !pendingAttachments.isEmpty else { return }

        let userMessage = ChatMessage(role: .user, text: trimmed, attachments: pendingAttachments)
        appendMessage(userMessage)
        messageText = ""
        pendingAttachments = []
        isInputFocused = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let reply = ChatMessage(role: .assistant, text: "Got it — I’ll keep this in mind. Want to go deeper?", attachments: [])
            appendMessage(reply)
        }
    }

    private func appendMessage(_ message: ChatMessage) {
        messagesByThread[selectedThreadId, default: []].append(message)
    }

    private func removeAttachment(_ attachment: ChatAttachment) {
        pendingAttachments.removeAll { $0.id == attachment.id }
    }
}

struct CoachSettingsView: View {
    @State private var useOwnKey: Bool = true
    @State private var apiKey: String = ""
    @State private var memoryEnabled: Bool = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Memory") {
                    Toggle("Remember context", isOn: $memoryEnabled)
                }

                Section("Model Access") {
                    Toggle("Bring your own API key", isOn: $useOwnKey)
                    if useOwnKey {
                        SecureField("Paste API key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    } else {
                        Text("App-managed keys can support subscriptions or daily message limits.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Coach Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct CoachProfile: Identifiable {
    let id: UUID
    let name: String
    let subtitle: String
    let systemImage: String

    static let runningId = UUID()
    static let dietId = UUID()
    static let therapyId = UUID()
}

struct ChatThread: Identifiable {
    let id: UUID
    let title: String
    let coachId: UUID

    static let sampleThreadId = UUID()
    static let sampleThreads: [ChatThread] = [
        ChatThread(id: sampleThreadId, title: "Lifting plan", coachId: CoachProfile.runningId),
        ChatThread(id: UUID(), title: "Sleep reset", coachId: CoachProfile.runningId)
    ]
}

enum ChatRole {
    case user
    case assistant
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let text: String
    let attachments: [ChatAttachment]

    static let sampleMessagesByThread: [UUID: [ChatMessage]] = [
        ChatThread.sampleThreadId: [
            ChatMessage(role: .assistant, text: "What are you training today?", attachments: []),
            ChatMessage(role: .user, text: "Upper body. I want to improve my pull-ups.", attachments: []),
            ChatMessage(role: .assistant, text: "Great. We can build a weekly plan. Any equipment limits?", attachments: [])
        ]
    ]
}

enum AttachmentKind {
    case photo
    case file
}

struct ChatAttachment: Identifiable {
    let id = UUID()
    let kind: AttachmentKind
    let name: String
}

struct CoachChip: View {
    let coach: CoachProfile
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: coach.systemImage)
                    .font(.headline)
                VStack(alignment: .leading, spacing: 2) {
                    Text(coach.name)
                        .font(.subheadline)
                        .bold()
                    Text(coach.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(isSelected ? Color.black : Color.secondary.opacity(0.12))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

struct ThreadChip: View {
    let title: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(title)
                .font(.subheadline)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(isSelected ? Color.black : Color.secondary.opacity(0.15))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct ChatBubble: View {
    let message: ChatMessage
    let maxWidth: CGFloat

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble
                Spacer()
            } else {
                Spacer()
                bubble
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: message.role == .assistant ? .leading : .trailing, spacing: 8) {
            if !message.text.isEmpty {
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(message.role == .assistant ? .primary : Color.white)
            }

            if !message.attachments.isEmpty {
                HStack(spacing: 6) {
                    ForEach(message.attachments) { attachment in
                        AttachmentBadge(attachment: attachment, isUser: message.role == .user)
                    }
                }
            }
        }
        .padding(12)
        .background(message.role == .assistant ? Color.secondary.opacity(0.15) : Color.blue.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: maxWidth, alignment: message.role == .assistant ? .leading : .trailing)
    }
}

struct AttachmentBadge: View {
    let attachment: ChatAttachment
    let isUser: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: attachment.kind == .photo ? "photo" : "doc")
                .font(.caption)
            Text(attachment.name)
                .font(.caption)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isUser ? Color.white.opacity(0.2) : Color.secondary.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(isUser ? Color.white : .primary)
    }
}

struct AttachmentChip: View {
    let attachment: ChatAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: attachment.kind == .photo ? "photo" : "doc")
            Text(attachment.name)
                .font(.caption)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
