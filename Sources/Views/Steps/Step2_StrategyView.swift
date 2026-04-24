import SwiftUI

// MARK: - Step 2: Search Strategy
struct Step2_StrategyView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var newTitle = ""
    @State private var newLocation = ""
    @State private var newIndustry = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("AI-Recommended Strategy")
                        .font(.largeTitle.bold())
                    Text("Review and customize your search filters")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 32)
                
                if let strategy = Binding($vm.searchStrategy) {
                    // Target Titles
                    FilterCard(title: "Target Titles", icon: "person.text.rectangle") {
                        FlowLayout(spacing: 6) {
                            ForEach(strategy.targetTitles.wrappedValue, id: \.self) { title in
                                RemovableChip(text: title, color: Color(hex: "#8b5cf6")) {
                                    strategy.targetTitles.wrappedValue.removeAll { $0 == title }
                                }
                            }
                        }
                        HStack {
                            TextField("Add title...", text: $newTitle)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") {
                                if !newTitle.isEmpty {
                                    strategy.targetTitles.wrappedValue.append(newTitle)
                                    newTitle = ""
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    // Seniority
                    FilterCard(title: "Seniority Levels", icon: "chart.bar.fill") {
                        let allSeniorities = ["entry", "senior", "manager", "director", "vp", "c_suite", "owner"]
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                            ForEach(allSeniorities, id: \.self) { level in
                                Toggle(level.replacingOccurrences(of: "_", with: " ").capitalized, isOn: Binding(
                                    get: { strategy.targetSeniorities.wrappedValue.contains(level) },
                                    set: { on in
                                        if on { strategy.targetSeniorities.wrappedValue.append(level) }
                                        else { strategy.targetSeniorities.wrappedValue.removeAll { $0 == level } }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .font(.callout)
                            }
                        }
                    }
                    
                    // Locations (Multi-region)
                    FilterCard(title: "Locations", icon: "globe.americas.fill") {
                        FlowLayout(spacing: 6) {
                            ForEach(strategy.locations.wrappedValue, id: \.self) { loc in
                                RemovableChip(text: loc, color: Color(hex: "#10b981")) {
                                    strategy.locations.wrappedValue.removeAll { $0 == loc }
                                }
                            }
                        }
                        HStack {
                            TextField("Add location (e.g., Germany, India)...", text: $newLocation)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") {
                                if !newLocation.isEmpty {
                                    strategy.locations.wrappedValue.append(newLocation)
                                    newLocation = ""
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        Picker("Search by", selection: strategy.locationMode) {
                            ForEach(LocationSearchMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    // Industries
                    FilterCard(title: "Industries", icon: "building.2.fill") {
                        FlowLayout(spacing: 6) {
                            ForEach(strategy.industries.wrappedValue, id: \.self) { ind in
                                RemovableChip(text: ind, color: Color(hex: "#3b82f6")) {
                                    strategy.industries.wrappedValue.removeAll { $0 == ind }
                                }
                            }
                        }
                        HStack {
                            TextField("Add industry...", text: $newIndustry)
                                .textFieldStyle(.roundedBorder)
                            Button("Add") {
                                if !newIndustry.isEmpty {
                                    strategy.industries.wrappedValue.append(newIndustry)
                                    newIndustry = ""
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    // Contact Count Slider
                    VStack(spacing: 12) {
                        HStack {
                            Text("How many contacts?")
                                .font(.headline)
                            Spacer()
                            Text("\(vm.settings.contactCount)")
                                .font(.title.bold())
                                .foregroundColor(Color(hex: "#8b5cf6"))
                        }
                        
                        Slider(value: Binding(
                            get: { Double(vm.settings.contactCount) },
                            set: { vm.settings.contactCount = Int($0) }
                        ), in: 10...1000, step: 10)
                        .tint(Color(hex: "#8b5cf6"))
                        
                        HStack {
                            Text("10").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text("250").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text("500").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text("1000").font(.caption).foregroundColor(.secondary)
                        }
                        
                        Text("Estimated enrichment cost: ~\(vm.settings.contactCount) credits")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(20)
                    .background(.regularMaterial)
                    .cornerRadius(12)
                    .padding(.horizontal, 40)
                }
                
                // Search Button
                Button {
                    Task { await vm.searchContacts() }
                } label: {
                    Label("Find Contacts", systemImage: "magnifyingglass")
                        .font(.body.bold())
                        .padding(.horizontal, 40)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#8b5cf6"))
                .disabled(vm.isLoading)
                
                if vm.isLoading {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(vm.loadingMessage)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer(minLength: 32)
            }
        }
    }
}

// MARK: - Filter Card
struct FilterCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .cornerRadius(12)
        .padding(.horizontal, 40)
    }
}

// MARK: - Removable Chip
struct RemovableChip: View {
    let text: String
    let color: Color
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(12)
    }
}
