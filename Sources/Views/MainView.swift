import SwiftUI

// MARK: - Main View
struct MainView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showSettings = false
    @State private var sidebarHover: AppStep? = nil
    
    var body: some View {
        NavigationSplitView {
            // MARK: - Sidebar
            VStack(alignment: .leading, spacing: 0) {
                // App Logo
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(LinearGradient(
                                colors: [Color(hex: "#8b5cf6"), Color(hex: "#3b82f6")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "bus.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Job Bus")
                            .font(.title3.bold())
                        Text("Outreach Manager")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 28)
                
                // Step Navigation
                VStack(spacing: 6) {
                    ForEach(AppStep.allCases) { step in
                        StepNavItem(
                            step: step,
                            isActive: vm.currentStep == step,
                            isComplete: step.rawValue < vm.currentStep.rawValue,
                            isHovered: sidebarHover == step
                        ) {
                            if step.rawValue <= vm.currentStep.rawValue {
                                // Warn if navigating away during generation
                                if vm.isGenerating && vm.currentStep == .drafts && step != .drafts {
                                    vm.showError("Email generation is in progress.\n\nCancel generation first or wait for it to complete before navigating away.")
                                    return
                                }
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    vm.currentStep = step
                                }
                            }
                        }
                        .onHover { hovering in
                            sidebarHover = hovering ? step : nil
                        }
                        .help(step.rawValue > vm.currentStep.rawValue
                              ? "Complete \(AppStep(rawValue: step.rawValue - 1)?.title ?? "previous") step first"
                              : step.title)
                    }
                }
                .padding(.horizontal, 12)
                
                Spacer()
                
                // Sandbox Banner
                if vm.settings.sandboxMode {
                    HStack(spacing: 6) {
                        Image(systemName: "flask.fill")
                            .font(.caption2)
                        Text("SANDBOX MODE")
                            .font(.caption2.bold())
                            .tracking(0.5)
                    }
                    .foregroundColor(.orange)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.orange.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                
                // Settings Button
                Divider()
                    .padding(.horizontal, 16)
                
                Button {
                    showSettings = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "gearshape.fill")
                            .font(.body)
                            .foregroundColor(.secondary)
                        Text("Settings")
                            .font(.body)
                            .foregroundColor(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.gray.opacity(0.4))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
            }
            .frame(minWidth: 220, idealWidth: 240)
        } detail: {
            // MARK: - Content Area
            ZStack {
                switch vm.currentStep {
                case .resume:
                    Step1_ResumeView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                case .strategy:
                    Step2_StrategyView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                case .contacts:
                    Step3_ContactsView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                case .drafts:
                    Step4_DraftsView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                case .send:
                    Step5_SendView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                }
                
                // Completion Banner overlay
                if vm.showCompletionBanner {
                    VStack {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(vm.completionMessage)
                                .font(.callout.weight(.medium))
                            Spacer()
                            Button {
                                withAnimation { vm.showCompletionBanner = false }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(.regularMaterial)
                        .cornerRadius(10)
                        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        
                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.currentStep)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .alert("Error", isPresented: $vm.showError) {
            if vm.canRetry {
                Button("Retry") { vm.performRetry() }
                    .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) { vm.showError = false }
            } else {
                Button("OK") { vm.showError = false }
            }
        } message: {
            Text(vm.errorMessage ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(vm)
        }
        // Keyboard shortcuts for step navigation
        .background(
            Group {
                Button("") { navigateToStep(0) }.keyboardShortcut("1", modifiers: .command)
                Button("") { navigateToStep(1) }.keyboardShortcut("2", modifiers: .command)
                Button("") { navigateToStep(2) }.keyboardShortcut("3", modifiers: .command)
                Button("") { navigateToStep(3) }.keyboardShortcut("4", modifiers: .command)
                Button("") { navigateToStep(4) }.keyboardShortcut("5", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        )
    }
    
    private func navigateToStep(_ rawValue: Int) {
        guard let step = AppStep(rawValue: rawValue),
              step.rawValue <= vm.currentStep.rawValue else { return }
        if vm.isGenerating && vm.currentStep == .drafts && step != .drafts { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            vm.currentStep = step
        }
    }
}

// MARK: - Step Navigation Item
struct StepNavItem: View {
    let step: AppStep
    let isActive: Bool
    let isComplete: Bool
    let isHovered: Bool
    let action: () -> Void
    
    private var isAccessible: Bool { isComplete || isActive }
    
    private var accentColor: Color {
        isActive ? Color(hex: "#8b5cf6") : isComplete ? Color(hex: "#10b981") : Color.gray.opacity(0.4)
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Step Indicator
                ZStack {
                    Circle()
                        .fill(isActive
                            ? LinearGradient(colors: [Color(hex: "#8b5cf6"), Color(hex: "#6366f1")], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : isComplete
                                ? LinearGradient(colors: [Color(hex: "#10b981"), Color(hex: "#059669")], startPoint: .topLeading, endPoint: .bottomTrailing)
                                : LinearGradient(colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 30, height: 30)
                    
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: step.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isActive ? .white : .secondary)
                    }
                }
                
                // Label
                Text(step.title)
                    .font(.body.weight(isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .primary : isComplete ? .primary.opacity(0.8) : .secondary)
                
                Spacer()
                
                // Step number
                if !isComplete && !isActive {
                    Text("\(step.rawValue + 1)")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.gray.opacity(0.4))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isActive ? Color(hex: "#8b5cf6").opacity(0.12)
                          : isHovered && isAccessible ? Color.primary.opacity(0.04)
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAccessible)
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
