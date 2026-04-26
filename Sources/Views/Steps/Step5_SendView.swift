import SwiftUI

// MARK: - Step 5: Send Campaign
struct Step5_SendView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var confirmText = ""
    @State private var showConfirmDialog = false
    
    /// Pre-flight check: SMTP must be configured (email + password, unless sandbox)
    var smtpReady: Bool {
        guard !vm.settings.smtpEmail.isEmpty else { return false }
        if vm.settings.sandboxMode { return true }
        let password = KeychainService.shared.get(key: .smtpPassword) ?? ""
        return !password.isEmpty
    }
    
    var approvedCount: Int { vm.drafts.filter { $0.status == .approved }.count }
    /// Use campaignTotal (captured at launch) for progress; fall back to approvedCount pre-launch
    var totalForProgress: Int { vm.campaignTotal > 0 ? vm.campaignTotal : approvedCount }
    var progress: Double {
        let total = Double(totalForProgress)
        return total > 0 ? min(Double(vm.sentCount + vm.failedCount) / total, 1.0) : 0
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Campaign")
                    .font(.largeTitle.bold())
                    .padding(.top, 32)
                
                // Sandbox Warning
                if vm.settings.sandboxMode {
                    HStack {
                        Image(systemName: "flask.fill")
                        VStack(alignment: .leading) {
                            Text("SANDBOX MODE — No real emails will be sent")
                                .font(.subheadline.bold())
                            Text("Emails go to localhost:\(vm.settings.sandboxPort). Switch in Settings to go live.")
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 40)
                }
                
                // No approved drafts warning
                if approvedCount == 0 && vm.campaignStatus == .idle {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No approved emails")
                                .font(.subheadline.bold())
                            Text("Go back to Compose and approve at least one draft before launching.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(8)
                    .padding(.horizontal, 40)
                }
                
                // SMTP not configured warning (EC6)
                if !smtpReady && vm.campaignStatus == .idle {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundColor(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SMTP not configured")
                                .font(.subheadline.bold())
                            Text(vm.settings.smtpEmail.isEmpty
                                ? "Go to Settings → Email and enter your email address and app password."
                                : "App password missing. Go to Settings → Email → App Password to set it.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(8)
                    .padding(.horizontal, 40)
                }
                
                // Progress Ring
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LinearGradient(colors: [Color(hex: "#8b5cf6"), Color(hex: "#3b82f6")],
                                          startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: 12, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut, value: progress)
                    
                    VStack(spacing: 4) {
                        Text("\(vm.sentCount + vm.failedCount)/\(totalForProgress)")
                            .font(.title.bold())
                        Text("\(Int(progress * 100))%")
                            .font(.title3)
                            .foregroundColor(Color(hex: "#8b5cf6"))
                        Text(vm.campaignStatus.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 180, height: 180)
                
                // Stats Cards
                HStack(spacing: 16) {
                    StatCard(icon: "checkmark.circle.fill", label: "Sent", value: vm.sentCount, color: "#10b981")
                        .help("Emails successfully delivered to the recipient's mail server")
                    StatCard(icon: "xmark.circle.fill", label: "Failed", value: vm.failedCount, color: "#ef4444")
                        .help("Emails that failed to send — check the activity log below for details")
                    StatCard(icon: "clock.fill", label: "Pending", value: max(0, totalForProgress - vm.sentCount - vm.failedCount), color: "#f59e0b")
                        .help("Approved emails still waiting to be sent")
                }
                .padding(.horizontal, 40)
                
                // Campaign Intelligence Card (pre-send only)
                if vm.campaignStatus == .idle && approvedCount > 0 {
                    let intel = CampaignIntelligence.analyze(
                        drafts: vm.drafts,
                        contacts: vm.contacts,
                        settings: vm.settings,
                        resumeFileURL: vm.resumeFileURL
                    )
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .font(.title3)
                                .foregroundColor(Color(hex: "#8b5cf6"))
                            Text("Campaign Intelligence")
                                .font(.headline)
                            Spacer()
                            
                            // Quality Score Ring
                            ZStack {
                                Circle()
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 4)
                                Circle()
                                    .trim(from: 0, to: Double(intel.qualityScore) / 100.0)
                                    .stroke(
                                        intel.qualityScore >= 70 ? Color(hex: "#10b981")
                                        : intel.qualityScore >= 40 ? Color(hex: "#f59e0b")
                                        : Color(hex: "#ef4444"),
                                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                                    )
                                    .rotationEffect(.degrees(-90))
                                Text("\(intel.qualityScore)")
                                    .font(.caption.bold().monospacedDigit())
                            }
                            .frame(width: 40, height: 40)
                        }
                        
                        // Breakdown
                        HStack(spacing: 16) {
                            Label("\(intel.breakdown.totalApproved) emails", systemImage: "envelope")
                            Label("\(intel.breakdown.resumeAttachCount) with resume", systemImage: "paperclip")
                            if intel.breakdown.linkOnlyCount > 0 {
                                Label("\(intel.breakdown.linkOnlyCount) link-only", systemImage: "link")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        // Risk Indicators
                        if !intel.riskIndicators.isEmpty {
                            Divider()
                            ForEach(intel.riskIndicators) { risk in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: risk.level.icon)
                                        .foregroundColor(Color(hex: risk.level.colorHex))
                                        .font(.caption)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(risk.title)
                                            .font(.caption.bold())
                                        Text(risk.detail)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        
                        // Suggestions
                        if !intel.suggestions.isEmpty {
                            Divider()
                            ForEach(intel.suggestions) { suggestion in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: suggestion.icon)
                                        .foregroundColor(Color(hex: "#3b82f6"))
                                        .font(.caption)
                                        .frame(width: 16)
                                    Text(suggestion.text)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.regularMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(
                                        intel.qualityScore < 40 ? Color(hex: "#ef4444").opacity(0.3)
                                        : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                    )
                    .padding(.horizontal, 40)
                }
                
                // Config Summary
                VStack(alignment: .leading, spacing: 8) {
                    Label("From: \(vm.settings.smtpEmail.isEmpty ? "Not configured" : vm.settings.smtpEmail)", systemImage: "envelope")
                    Label("Delay: \(Int(vm.settings.delaySeconds)) seconds between emails", systemImage: "timer")
                    Label("Schedule: \(vm.settings.businessHoursStart):00 - \(vm.settings.businessHoursEnd):00", systemImage: "clock")
                    Label("Daily limit: \(vm.settings.maxPerDay) emails", systemImage: "chart.bar")
                    if let resumeURL = vm.resumeFileURL {
                        Label("Resume: \(resumeURL.lastPathComponent)", systemImage: "doc.fill")
                    }
                }
                .font(.callout)
                .foregroundColor(.secondary)
                .padding(16)
                .background(.regularMaterial)
                .cornerRadius(8)
                .padding(.horizontal, 40)
                
                // Paused Message
                if vm.campaignStatus == .paused {
                    HStack {
                        Image(systemName: "pause.circle.fill")
                            .foregroundColor(.orange)
                        Text(vm.loadingMessage)
                            .font(.callout)
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal, 40)
                }
                
                // Running message
                if vm.campaignStatus == .running {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(vm.loadingMessage)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(.regularMaterial)
                    .cornerRadius(8)
                    .padding(.horizontal, 40)
                }
                
                // Send Log
                if !vm.sendRecords.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Activity")
                            .font(.headline)
                        
                        ForEach(vm.sendRecords.suffix(10).reversed()) { record in
                            HStack {
                                Text(record.sentAt?.formatted(.dateTime.hour().minute()) ?? "")
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                                Image(systemName: record.status == .sent ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(record.status == .sent ? .green : .red)
                                    .font(.caption)
                                Text(record.recipientName)
                                    .font(.caption.weight(.medium))
                                Text(record.recipientEmail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                if let error = record.errorMessage {
                                    Text("(\(error))")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial)
                    .cornerRadius(8)
                    .padding(.horizontal, 40)
                }
                
                // Action Buttons
                HStack(spacing: 16) {
                    switch vm.campaignStatus {
                    case .idle:
                        Button {
                            showConfirmDialog = true
                        } label: {
                            Label("Launch Campaign", systemImage: "paperplane.fill")
                                .font(.body.bold())
                                .padding(.horizontal, 32)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(hex: "#8b5cf6"))
                        .disabled(approvedCount == 0 || !smtpReady)
                        .help(approvedCount == 0 ? "Approve at least one draft first" : !smtpReady ? "Configure SMTP in Settings first" : "Send \(approvedCount) approved emails")
                        
                    case .running:
                        Button { vm.pauseCampaign() } label: {
                            Label("Pause", systemImage: "pause.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        
                        Button { vm.stopCampaign() } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        
                    case .paused:
                        Button { vm.resumeCampaign() } label: {
                            Label("Resume", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        
                        Button { vm.stopCampaign() } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        
                    case .complete:
                        VStack(spacing: 8) {
                            Label("Campaign Complete", systemImage: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.title3.bold())
                            Text("\(vm.sentCount) sent, \(vm.failedCount) failed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                    case .stopped:
                        VStack(spacing: 8) {
                            Label("Campaign Stopped", systemImage: "stop.circle.fill")
                                .foregroundColor(.red)
                                .font(.title3.bold())
                            Text("\(vm.sentCount) sent before stop")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button {
                                vm.campaignStatus = .idle
                            } label: {
                                Label("Reset", systemImage: "arrow.counterclockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(.top, 8)
                
                Spacer(minLength: 32)
            }
        }
        .sheet(isPresented: $showConfirmDialog) {
            ConfirmSendSheet(
                count: approvedCount,
                confirmText: $confirmText,
                onConfirm: {
                    vm.startCampaign()
                }
            )
        }
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let icon: String
    let label: String
    let value: Int
    let color: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(Color(hex: color))
            Text("\(value)")
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.regularMaterial)
        .cornerRadius(12)
    }
}

// MARK: - Confirm Send Dialog (Type to confirm)
struct ConfirmSendSheet: View {
    let count: Int
    @Binding var confirmText: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var expectedText: String { "SEND \(count)" }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)
            
            Text("FINAL CONFIRMATION")
                .font(.title2.bold())
            
            Text("You are about to send \(count) emails.\nThis action CANNOT be undone.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Type \"\(expectedText)\" to confirm:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("", text: $confirmText)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
            }
            
            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Send") {
                    onConfirm()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(confirmText != expectedText)
            }
        }
        .padding(32)
        .frame(width: 400)
        .onAppear { confirmText = "" }
    }
}
