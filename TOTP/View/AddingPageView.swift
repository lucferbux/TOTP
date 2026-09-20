//
//  AddingPageView.swift
//  TOTP
//
//  Add / edit form. New accounts can be filled from a QR code (camera or image),
//  a pasted otpauth:// link, or typed manually.
//

import SwiftUI
import PhotosUI

public struct AddingPageView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var syncManager: SyncManager

    private let editingAccount: OtpModel?

    @State private var issuer = ""
    @State private var name = ""
    @State private var prefix = ""
    @State private var key = ""
    @State private var digits = 6
    @State private var interval = 30
    @State private var counter = 0
    @State private var isHotp = false
    @State private var algorithm = OtpAlgorithm.sha1
    @State private var domainsText = ""

    @State private var showKey = false
    @State private var showPrefix = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var importedFromCode = false
    @State private var showScanner = false
    @State private var photoItem: PhotosPickerItem?

    private var isEditing: Bool { editingAccount != nil }

    private var canSave: Bool {
        !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    public init(editingAccount: OtpModel? = nil, prefill: OtpAuthURL? = nil) {
        self.editingAccount = editingAccount
        let entry: OtpEntry?
        if let account = editingAccount {
            _issuer = State(initialValue: account.issuer ?? "")
            _name = State(initialValue: account.name ?? "")
            _prefix = State(initialValue: account.prefix ?? "")
            _domainsText = State(initialValue: (account.associatedDomains ?? []).joined(separator: ", "))
            entry = account.entry
        } else if let prefill {
            _issuer = State(initialValue: prefill.issuer ?? "")
            _name = State(initialValue: prefill.name ?? "")
            _importedFromCode = State(initialValue: true)
            entry = prefill.entry
        } else {
            entry = nil
        }
        if let entry {
            // Secrets are always shown as Base32, the format every service hands out.
            _key = State(initialValue: entry.key.base32EncodedString())
            _isHotp = State(initialValue: entry.isHotp)
            _digits = State(initialValue: entry.digits)
            _interval = State(initialValue: Int(entry.interval ?? 30))
            _counter = State(initialValue: Int(clamping: entry.counter ?? 0))
            _algorithm = State(initialValue: entry.algorithm)
        }
    }

    public var body: some View {
        NavigationStack {
            Form {
                if !isEditing {
                    quickSetupSection
                }
                accountSection
                secretSection
                prefixSection
                autoFillSection
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Account" : "Add Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("cancelButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        Task { await save() }
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("saveButton")
                }
            }
            .disabled(isSaving)
            .overlay {
                if isSaving {
                    ProgressView()
                        .controlSize(.large)
                        .padding(24)
                        .floatingGlass(in: .rect(cornerRadius: 20))
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 540, idealHeight: 640)
        #endif
        .alert("Can't Save Account", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerView { payload in
                showScanner = false
                apply(scanned: payload)
            } onCancel: {
                showScanner = false
            }
        }
        #endif
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await importImage(item) }
        }
    }

    // MARK: - Sections

    private var quickSetupSection: some View {
        Section {
            #if os(iOS)
            if QRScannerView.isAvailable {
                Button {
                    showScanner = true
                } label: {
                    Label("Scan QR Code", systemImage: "qrcode.viewfinder")
                }
                .accessibilityIdentifier("scanQRButton")
            }
            #endif
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choose QR Code Image", systemImage: "photo.on.rectangle")
            }
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first else { return }
                Task { @MainActor in apply(scanned: text) }
            }
            .accessibilityIdentifier("pasteLinkButton")
        } header: {
            Text("Quick Setup")
        } footer: {
            if importedFromCode {
                Label("Details filled in from the setup code. Review them, then tap Add.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Scan the QR code shown when you turn on two-factor authentication, or paste an otpauth:// link.")
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            TextField("Issuer", text: $issuer, prompt: Text("e.g. Example Corp"))
                .textContentType(.organizationName)
                .autocorrectionDisabled()
                .accessibilityIdentifier("issuerField")
            TextField("Account Name", text: $name, prompt: Text("e.g. user@example.com"))
                .textContentType(.username)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .accessibilityIdentifier("nameField")
        }
    }

    private var secretSection: some View {
        Section {
            HStack {
                Group {
                    if showKey {
                        TextField("Secret Key", text: $key)
                            #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            #endif
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                    } else {
                        SecureField("Secret Key", text: $key)
                    }
                }
                .accessibilityIdentifier("secretField")
                revealButton(isOn: $showKey, label: "Show Secret Key")
            }

            Picker("Type", selection: $isHotp) {
                Text("Time-based (TOTP)").tag(false)
                Text("Counter-based (HOTP)").tag(true)
            }
            .disabled(isEditing)

            if isHotp {
                Stepper("Counter: \(counter)", value: $counter, in: 0...Int(Int32.max))
            } else {
                Stepper("Refresh every \(interval) s", value: $interval, in: 1...300)
            }
            Stepper("\(digits) digits", value: $digits, in: 6...10)
            Picker("Algorithm", selection: $algorithm) {
                ForEach(OtpAlgorithm.allCases) { algorithm in
                    Text(algorithm.displayName).tag(algorithm)
                }
            }
        } header: {
            Text("Secret")
        } footer: {
            Text("Most services use time-based codes with 6 digits, 30 seconds and SHA-1.")
        }
    }

    private var prefixSection: some View {
        Section {
            HStack {
                Group {
                    if showPrefix {
                        TextField("Prefix", text: $prefix, prompt: Text("Optional"))
                            .font(.body.monospaced())
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .autocorrectionDisabled()
                    } else {
                        SecureField("Prefix", text: $prefix, prompt: Text("Optional"))
                    }
                }
                .accessibilityIdentifier("prefixField")
                revealButton(isOn: $showPrefix, label: "Show Prefix")
            }
        } header: {
            Text("Fixed Prefix (PIN)")
        } footer: {
            Text("Added before the code when you copy it or use AutoFill, for services that expect a PIN followed by the code. It's never shown on screen.")
        }
    }

    private var autoFillSection: some View {
        Section {
            TextField("Domains", text: $domainsText, prompt: Text("e.g. sso.example.com"))
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .autocorrectionDisabled()
                .accessibilityIdentifier("domainsField")
        } header: {
            Text("AutoFill Domains")
        } footer: {
            Text("Websites where AutoFill should suggest this code, separated by commas.")
        }
    }

    private func revealButton(isOn: Binding<Bool>, label: LocalizedStringKey) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: isOn.wrappedValue ? "eye.slash" : "eye")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .accessibilityLabel(Text(label))
    }

    // MARK: - Import

    private func apply(scanned payload: String) {
        do {
            let parsed = try OtpAuthURL(string: payload)
            withAnimation(.smooth(duration: 0.3)) {
                if let issuer = parsed.issuer { self.issuer = issuer }
                if let name = parsed.name { self.name = name }
                key = parsed.entry.key.base32EncodedString()
                isHotp = parsed.entry.isHotp
                digits = parsed.entry.digits
                interval = Int(parsed.entry.interval ?? 30)
                counter = Int(clamping: parsed.entry.counter ?? 0)
                algorithm = parsed.entry.algorithm
                importedFromCode = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importImage(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let payloads = try await QRCodeDecoder.payloads(inImageData: data)
            guard let payload = payloads.first(where: { $0.lowercased().hasPrefix("otpauth://") }) ?? payloads.first else {
                errorMessage = String(localized: "No QR code was found in that image.")
                return
            }
            apply(scanned: payload)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Save

    @MainActor
    private func save() async {
        let issuer = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let domains = domainsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard let keyData = Data(base32Encoded: key) else {
            errorMessage = String(localized: "The secret key isn't valid. It should contain only the letters A–Z and the digits 2–7.")
            return
        }

        let entry: OtpEntry = isHotp
            ? .hotp(key: keyData, digits: digits, counter: UInt64(max(0, counter)), algorithm: algorithm)
            : .totp(key: keyData, digits: digits, interval: Double(interval), algorithm: algorithm)

        isSaving = true
        defer { isSaving = false }

        if var updated = editingAccount {
            updated.issuer = issuer.isEmpty ? nil : issuer
            updated.name = name.isEmpty ? nil : name
            updated.prefix = prefix.isEmpty ? nil : prefix
            updated.entry = entry
            updated.associatedDomains = domains.isEmpty ? nil : domains
            do {
                try await syncManager.updateAccount(updated)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        } else {
            let account = OtpModel(
                issuer: issuer.isEmpty ? nil : issuer,
                name: name.isEmpty ? nil : name,
                prefix: prefix.isEmpty ? nil : prefix,
                entry: entry,
                associatedDomains: domains.isEmpty ? nil : domains
            )
            await syncManager.addAccount(account)
        }
        dismiss()
    }
}

#Preview("Add") {
    AddingPageView()
        .environmentObject(SyncManager.shared)
}

#Preview("Edit") {
    AddingPageView(editingAccount: .preview(issuer: "Example Corp", name: "user@example.com", prefix: "1234"))
        .environmentObject(SyncManager.shared)
}
