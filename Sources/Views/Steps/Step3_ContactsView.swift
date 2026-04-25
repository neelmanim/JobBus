import SwiftUI
import UniformTypeIdentifiers

// MARK: - Step 3: Contacts List
struct Step3_ContactsView: View {
    @EnvironmentObject var vm: AppViewModel
    @State private var showCSVImport = false
    @State private var showManualEntry = false
    @State private var searchText = ""
    @State private var selectedSource: ContactSource?
    
    var filteredContacts: [Contact] {
        var result = vm.contacts
        if let source = selectedSource { result = result.filter { $0.source == source } }
        if !searchText.isEmpty {
            result = result.filter {
                $0.fullName.localizedCaseInsensitiveContains(searchText) ||
                $0.email.localizedCaseInsensitiveContains(searchText) ||
                $0.company.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Text("Contacts")
                    .font(.largeTitle.bold())
                
                // Source Buttons
                HStack(spacing: 12) {
                    Button {
                        Task { await vm.searchContacts() }
                    } label: {
                        if vm.isSearching {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Searching...")
                            }
                        } else {
                            Label("Apollo Search", systemImage: "magnifyingglass")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#8b5cf6"))
                    .disabled(vm.isSearching || vm.isGenerating || vm.isLoading)
                    
                    if vm.isSearching {
                        Button {
                            vm.cancelSearch()
                        } label: {
                            Label("Cancel", systemImage: "xmark.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    
                    Button { showCSVImport = true } label: {
                        Label("Import CSV", systemImage: "doc.text.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#3b82f6"))
                    .disabled(vm.isSearching || vm.isGenerating)
                    
                    Button { showManualEntry = true } label: {
                        Label("Manual Entry", systemImage: "pencil.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#10b981"))
                    .disabled(vm.isSearching || vm.isGenerating)
                }
                
                // Loading Message
                if vm.isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(vm.loadingMessage)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                // Summary
                if !vm.contacts.isEmpty {
                    HStack(spacing: 16) {
                        Text("\(vm.contacts.count) total contacts")
                            .font(.subheadline.bold())
                        
                        let sources = Dictionary(grouping: vm.contacts, by: \.source)
                        ForEach(Array(sources.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { source in
                            Text("\(source.rawValue): \(sources[source]?.count ?? 0)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: source.color).opacity(0.15))
                                .foregroundColor(Color(hex: source.color))
                                .cornerRadius(8)
                        }
                    }
                    
                    // Search + Filter
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search contacts...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(.regularMaterial)
                    .cornerRadius(8)
                    .padding(.horizontal, 20)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 12)
            
            if vm.contacts.isEmpty && !vm.isSearching {
                // Empty state
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("No contacts yet")
                        .font(.title2.weight(.medium))
                        .foregroundColor(.secondary)
                    Text("Search Apollo, import a CSV, or add contacts manually to get started.")
                        .font(.callout)
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 350)
                }
                Spacer()
            } else {
                // Contacts Table
                Table(filteredContacts) {
                    TableColumn("") { contact in
                        Toggle("", isOn: Binding(
                            get: { contact.isSelected },
                            set: { val in
                                if let i = vm.contacts.firstIndex(where: { $0.id == contact.id }) {
                                    vm.contacts[i].isSelected = val
                                }
                            }
                        ))
                    }
                    .width(30)
                    
                    TableColumn("Source") { contact in
                        Image(systemName: contact.source.icon)
                            .foregroundColor(Color(hex: contact.source.color))
                    }
                    .width(40)
                    
                    TableColumn("Name") { contact in
                        Text(contact.fullName)
                            .font(.body.weight(.medium))
                    }
                    .width(min: 120, ideal: 160)
                    
                    TableColumn("Title") { contact in
                        Text(contact.title)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .width(min: 120, ideal: 180)
                    
                    TableColumn("Company") { contact in
                        Text(contact.company)
                            .font(.callout)
                    }
                    .width(min: 100, ideal: 140)
                    
                    TableColumn("Email") { contact in
                        Text(contact.email)
                            .font(.callout)
                            .foregroundColor(contact.email.isEmpty ? .red : .primary)
                    }
                    .width(min: 150, ideal: 200)
                    
                    TableColumn("Type") { contact in
                        Text(contact.recipientType.label)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#8b5cf6").opacity(0.12))
                            .cornerRadius(6)
                    }
                    .width(min: 80, ideal: 110)
                    
                    TableColumn("Relevance") { contact in
                        if contact.relevanceScore > 0 {
                            let label = contact.relevanceScore >= 0.6 ? "High"
                                      : contact.relevanceScore >= 0.3 ? "Med"
                                      : "Low"
                            let color = contact.relevanceScore >= 0.6 ? "#10b981"
                                      : contact.relevanceScore >= 0.3 ? "#f59e0b"
                                      : "#6b7280"
                            Text(label)
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(hex: color).opacity(0.12))
                                .foregroundColor(Color(hex: color))
                                .cornerRadius(6)
                                .help(contact.relevanceReason)
                        } else {
                            Text("—")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .width(min: 60, ideal: 80)
                }
            }
            
            // Bottom Bar
            HStack {
                let selected = vm.contacts.filter { $0.isSelected && !$0.email.isEmpty }.count
                Text("\(selected) contacts selected for outreach")
                    .font(.callout)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button {
                    Task { await vm.generateDrafts() }
                } label: {
                    if vm.isGenerating {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Generating...")
                        }
                    } else {
                        // Smart label: show what the button will actually do
                        let existingIds = Set(vm.drafts.filter { $0.status != .failed }.map { $0.contactId })
                        let selectedIds = Set(vm.contacts.filter { $0.isSelected && !$0.email.isEmpty }.map { $0.id })
                        let newCount = selectedIds.subtracting(existingIds).count
                        
                        if newCount == 0 && !vm.drafts.isEmpty {
                            Label("View Drafts", systemImage: "envelope.open.fill")
                                .font(.body.bold())
                        } else if newCount < selected {
                            Label("Compose \(newCount) New", systemImage: "envelope.fill")
                                .font(.body.bold())
                        } else {
                            Label("Compose Emails", systemImage: "envelope.fill")
                                .font(.body.bold())
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#8b5cf6"))
                .disabled(selected == 0 || vm.isGenerating || vm.isSearching)
            }
            .padding(16)
            .background(.bar)
        }
        .sheet(isPresented: $showCSVImport) {
            CSVImportSheet()
        }
        .sheet(isPresented: $showManualEntry) {
            ManualEntrySheet()
        }
    }
}

// MARK: - CSV Import Sheet
struct CSVImportSheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var importResult: CSVImporter.ImportResult?
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Import CSV")
                .font(.title2.bold())
            
            if let result = importResult {
                VStack(spacing: 8) {
                    Text("Found \(result.contacts.count) contacts with valid emails")
                        .font(.body)
                    Text("Skipped \(result.skippedRows) rows (missing or invalid email)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.bordered)
                    Button("Import \(result.contacts.count) Contacts") {
                        for contact in result.contacts {
                            vm.addManualContact(contact)
                        }
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#3b82f6"))
                }
            } else {
                // Drop zone
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .foregroundColor(isDragging ? .blue : .gray.opacity(0.4))
                    
                    VStack(spacing: 8) {
                        Image(systemName: "doc.text.fill")
                            .font(.title)
                        Text("Drop CSV file here")
                        Button("Browse") { openCSVPicker() }
                            .buttonStyle(.bordered)
                    }
                }
                .frame(height: 150)
                .onDrop(of: [UTType.commaSeparatedText, UTType.data], isTargeted: $isDragging) { providers in
                    handleCSVDrop(providers: providers)
                    return true
                }
            }
        }
        .padding(32)
        .frame(width: 450, height: 300)
    }
    
    private func openCSVPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText, UTType(filenameExtension: "csv")!]
        if panel.runModal() == .OK, let url = panel.url {
            importResult = try? vm.csvImporter.parseCSV(from: url)
        }
    }
    
    private func handleCSVDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.data.identifier) { item, _ in
                if let url = item as? URL {
                    Task { @MainActor in
                        importResult = try? vm.csvImporter.parseCSV(from: url)
                    }
                }
            }
        }
    }
}

// MARK: - Manual Entry Sheet
struct ManualEntrySheet: View {
    @EnvironmentObject var vm: AppViewModel
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var title = ""
    @State private var company = ""
    @State private var bulkEmails = ""
    @State private var mode: EntryMode = .single
    
    enum EntryMode: String, CaseIterable { case single = "Single", bulk = "Bulk Paste" }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Add Contacts")
                .font(.title2.bold())
            
            Picker("Mode", selection: $mode) {
                ForEach(EntryMode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            
            if mode == .single {
                TextField("Email *", text: $email).textFieldStyle(.roundedBorder)
                HStack {
                    TextField("First Name", text: $firstName).textFieldStyle(.roundedBorder)
                    TextField("Last Name", text: $lastName).textFieldStyle(.roundedBorder)
                }
                TextField("Title", text: $title).textFieldStyle(.roundedBorder)
                TextField("Company", text: $company).textFieldStyle(.roundedBorder)
                
                HStack {
                    Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                    Button("Add Contact") {
                        vm.addManualContact(Contact(
                            firstName: firstName, lastName: lastName,
                            email: email, title: title, company: company,
                            source: .manual, status: .added
                        ))
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#10b981"))
                    .disabled(email.isEmpty)
                }
            } else {
                Text("Paste emails, one per line:")
                    .font(.caption).foregroundColor(.secondary)
                TextEditor(text: $bulkEmails)
                    .font(.body.monospaced())
                    .frame(height: 120)
                    .border(Color.gray.opacity(0.3))
                
                HStack {
                    Button("Cancel") { dismiss() }.buttonStyle(.bordered)
                    Button("Add All") {
                        let emails = bulkEmails.components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        for e in emails {
                            vm.addManualContact(Contact(email: e, source: .manual, status: .added))
                        }
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "#10b981"))
                }
            }
        }
        .padding(32)
        .frame(width: 450, height: mode == .single ? 350 : 320)
    }
}
