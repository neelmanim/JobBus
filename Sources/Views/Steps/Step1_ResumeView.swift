import SwiftUI

// MARK: - Step 1: Resume Upload
struct Step1_ResumeView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var isDragOver = false
    @State private var pulseAnimation = false
    
    var body: some View {
        VStack(spacing: 0) {
            if vm.resumeProfile == nil {
                uploadState
            } else {
                profileState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Upload State
    private var uploadState: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Title
            VStack(spacing: 8) {
                Text("Upload Your Resume")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text("Drop a PDF or DOCX and AI will analyze your profile")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            // Drop Zone
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(isDragOver
                        ? Color(hex: "#8b5cf6").opacity(0.08)
                        : Color.primary.opacity(0.02))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                isDragOver ? Color(hex: "#8b5cf6") : Color.primary.opacity(0.1),
                                style: StrokeStyle(lineWidth: isDragOver ? 2 : 1.5, dash: [8, 6])
                            )
                    )
                    .animation(.easeInOut(duration: 0.2), value: isDragOver)
                
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "#8b5cf6").opacity(0.1))
                            .frame(width: 72, height: 72)
                            .scaleEffect(pulseAnimation ? 1.05 : 1.0)
                        
                        Image(systemName: isDragOver ? "arrow.down.doc.fill" : "doc.text.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(LinearGradient(
                                colors: [Color(hex: "#8b5cf6"), Color(hex: "#6366f1")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                    }
                    
                    VStack(spacing: 6) {
                        Text(isDragOver ? "Release to upload" : "Drop your resume here")
                            .font(.title3.weight(.semibold))
                        
                        Text("PDF or DOCX format")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    
                    // Browse button
                    Button {
                        openFile()
                    } label: {
                        Label("Browse Files", systemImage: "folder.fill")
                            .font(.body.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(
                                LinearGradient(
                                    colors: [Color(hex: "#8b5cf6"), Color(hex: "#6366f1")],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 500, maxHeight: 280)
            .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                handleDrop(providers)
            }
            
            // Loading overlay
            if vm.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.9)
                    Text(vm.loadingMessage)
                        .font(.callout.weight(.medium))
                        .foregroundColor(.secondary)
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Spacer()
        }
        .padding(40)
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
    }
    
    // MARK: - Profile State (After Analysis)
    private var profileState: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let profile = vm.resumeProfile {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Resume Analyzed")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                            Text("AI has extracted your profile. Review and proceed to strategy.")
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        
                        Button {
                            withAnimation { vm.resumeProfile = nil }
                        } label: {
                            Label("Upload New", systemImage: "arrow.counterclockwise")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // Profile Card
                    ProfileCard(profile: profile)
                    
                    // Continue
                    HStack {
                        Spacer()
                        Button {
                            withAnimation { vm.currentStep = .strategy }
                        } label: {
                            Label("Continue to Strategy", systemImage: "arrow.right")
                                .font(.body.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(
                                        colors: [Color(hex: "#8b5cf6"), Color(hex: "#6366f1")],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(32)
        }
    }
    
    // MARK: - Helpers
    
    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .init(filenameExtension: "docx")!]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select your resume (PDF or DOCX)"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task { await vm.parseResume(from: url) }
        }
    }
    
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            let ext = url.pathExtension.lowercased()
            guard ext == "pdf" || ext == "docx" else { return }
            Task { @MainActor in
                await vm.parseResume(from: url)
            }
        }
        return true
    }
}

// MARK: - Profile Card
struct ProfileCard: View {
    let profile: ResumeProfile
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Name and Role
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: "#8b5cf6"), Color(hex: "#3b82f6")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 52, height: 52)
                    
                    Text(profile.name.prefix(1))
                        .font(.title2.bold())
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.title3.bold())
                    Text(profile.currentRole)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if profile.yearsExperience > 0 {
                    VStack(spacing: 2) {
                        Text("\(profile.yearsExperience)")
                            .font(.title2.bold())
                            .foregroundColor(Color(hex: "#8b5cf6"))
                        Text("years exp")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(hex: "#8b5cf6").opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            
            Divider()
            
            // Skills
            if !profile.skills.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Skills", systemImage: "star.fill")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    
                    FlowLayout(spacing: 6) {
                        ForEach(profile.skills.prefix(15), id: \.self) { skill in
                            Text(skill)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(hex: "#8b5cf6").opacity(0.1))
                                .foregroundColor(Color(hex: "#8b5cf6"))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            
            // Key Achievements
            if !profile.achievements.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Key Achievements", systemImage: "trophy.fill")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    
                    ForEach(profile.achievements.prefix(3), id: \.self) { achievement in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(hex: "#10b981"))
                                .font(.caption)
                                .padding(.top, 2)
                            Text(achievement)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - Flow Layout (Wrapping Tags)
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        
        return (positions, CGSize(width: maxWidth, height: y + rowHeight))
    }
}
