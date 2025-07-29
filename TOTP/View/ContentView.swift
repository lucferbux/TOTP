import Combine
import CryptoKit
import SwiftUI
import CloudKit

#if canImport(UIKit)
    import UIKit
#endif

public struct ContentView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var dataManager = SharedDataManager.shared
    @State private var accounts: [OtpModel] = []
    @State var addingAccount = false
    @State var editingAccount: OtpModel?
    @State var deletingAccount: OtpModel?
    @State var showCopiedToast = false
    @State var search = ""
    @State private var showingErrorAlert = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                VStack {
                    GeometryReader { geometry in
                        ScrollView {
                            ZStack {
                                // Content when accounts exist or loading
                                if !self.accounts.isEmpty || dataManager.isLoading {
                                    VStack {
                                        let searchField = self.search.trimmingCharacters(
                                            in: .whitespacesAndNewlines)
                                        LazyVGrid(
                                            columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: geometry.size.width > 768 ? 3 : 1),
                                            alignment: .center,
                                            spacing: 12
                                        ) {
                                            ForEach(
                                                searchField.isEmpty
                                                    ? self.accounts
                                                    : self.accounts
                                                        .filter {
                                                            $0.name?.localizedCaseInsensitiveContains(
                                                                searchField) ?? false
                                                                || $0
                                                                    .issuer?
                                                                    .localizedCaseInsensitiveContains(
                                                                        searchField) ?? false
                                                        }
                                            ) { account in
                                                TOtpView(
                                                    otp: account,
                                                    cutoff: geometry.size.width,
                                                    deleting: $deletingAccount,
                                                    editing: $editingAccount,
                                                    toast: $showCopiedToast
                                                )
                                                .transition(
                                                    AnyTransition.asymmetric(
                                                        insertion: AnyTransition.move(edge: .leading),
                                                        removal: AnyTransition.move(edge: .trailing)
                                                    ).combined(with: AnyTransition.opacity)
                                                )
                                            }
                                        }
                                        .padding(.top)
                                        .padding(.horizontal, geometry.size.width > 768 ? 40 : 20)
                                        .frame(minWidth: geometry.size.width, maxWidth: geometry.size.width)

                                        // Loading indicator
                                        if dataManager.isLoading {
                                            VStack {
                                                ProgressView()
                                                    .scaleEffect(1.2)
                                                Text("Loading accounts...")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .padding(.top, 8)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                        }

                                        // Instructions for existing accounts
                                        if !self.accounts.isEmpty {
                                            Spacer()
                                                .frame(height: 20)
                                        }
                                    }
                                }
                                
                                // Empty state - properly centered
                                if self.accounts.isEmpty && !dataManager.isLoading {
                                    VStack(spacing: 20) {
                                        Image(systemName: "lock.shield")
                                            .font(.system(size: 60))
                                            .foregroundColor(.secondary)
                                        VStack(spacing: 8) {
                                            Text("No TOTP accounts")
                                                .font(.title2)
                                                .fontWeight(.semibold)
                                            Text("Add your first account to get started")
                                                .font(.body)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                                }
                            }
                        }
                        .refreshable {
                            dataManager.loadAccounts()
                        }
                        
                        // Toast message overlay
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text("Code copied to clipboard")
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(
                                        .regularMaterial,
                                        in: RoundedRectangle(cornerRadius: 12))
                                Spacer()
                            }
                            .opacity(self.showCopiedToast ? 0.9 : 0.0)
                            .allowsHitTesting(false)
                            .padding()
                        }
                    }
                }
                
                // Floating Action Button (iOS only)
                #if os(iOS)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            self.addingAccount = true
                        }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.4, green: 0.5, blue: 1.0),
                                            Color(red: 0.6, green: 0.4, blue: 0.9)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 30)
                    }
                }
                #endif
            }
            .navigationTitle("TOTP Passwords")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
            #elseif os(macOS)
                .toolbar {
                    ToolbarItem(placement: .secondaryAction) {
                        Button(action: {
                            dataManager.loadAccounts()
                        }) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .help("Refresh accounts")
                        .disabled(dataManager.isLoading)
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            self.addingAccount = true
                        }) {
                            Label("Add Account", systemImage: "plus")
                        }
                        .help("Add new TOTP account")
                    }
                }
            #endif
        }
        .onAppear {
            self.accounts = dataManager.accounts
        }
        .onReceive(dataManager.$accounts) { newAccounts in
            withAnimation(.easeInOut(duration: 0.3)) {
                self.accounts = newAccounts
            }
        }
        .onReceive(dataManager.$error) { error in
            if error != nil {
                showingErrorAlert = true
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Data Error", isPresented: $showingErrorAlert) {
            Button("OK") {
                dataManager.error = nil
            }
        } message: {
            Text(dataManager.error?.localizedDescription ?? "An unknown error occurred")
        }
        .alert(item: $deletingAccount) { (item: OtpModel) in
            var alertText: String
            switch (item.issuer, item.name) {
            case let (.some(issuer), .some(name)):
                alertText = "the account \"\(name)\" for \"\(issuer)\""
            case let (.none, .some(name)):
                alertText = "the account \"\(name)\""
            case let (.some(issuer), .none):
                alertText = "the account for \"\(issuer)\""
            case (.none, .none):
                alertText = "this account"
            }
            return Alert(
                title: Text("Confirm Delete"),
                message: Text("Are you sure that you want to DELETE \(alertText)"),
                primaryButton: .destructive(Text("Delete").bold()) {
                    dataManager.deleteAccount(item)
                    withAnimation(Animation.easeInOut(duration: 1)) {
                        self.accounts.removeAll(where: { $0.id == item.id })
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $addingAccount) {
            AddingPageView(
                accounts: $accounts, addingAccount: $addingAccount, dataManager: dataManager
            )
            .preferredColorScheme(self.colorScheme)
        }
        .sheet(item: $editingAccount) { account in
            AddingPageView(
                accounts: $accounts, addingAccount: .constant(false), dataManager: dataManager
            )
            .preferredColorScheme(self.colorScheme)
            .onDisappear {
                editingAccount = nil
            }
        }
    }
}

struct ContentViewPreviewLight: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.light)
    }
}

struct ContentViewPreviewDark: PreviewProvider {
    static var previews: some View {
        ContentView()
            .preferredColorScheme(.dark)
    }
}

// Preview with empty state
struct ContentViewEmptyPreview: PreviewProvider {
    static var previews: some View {
        Group {
            ContentViewEmpty()
                .preferredColorScheme(.light)
                .previewDisplayName("Empty State - Light")
            
            ContentViewEmpty()
                .preferredColorScheme(.dark)
                .previewDisplayName("Empty State - Dark")
        }
    }
}

// Preview with sample data
struct ContentViewWithDataPreview: PreviewProvider {
    static var previews: some View {
        Group {
            ContentViewWithSampleData()
                .preferredColorScheme(.light)
                .previewDisplayName("With Data - Light")
            
            ContentViewWithSampleData()
                .preferredColorScheme(.dark)
                .previewDisplayName("With Data - Dark")
        }
    }
}

// Mock view for empty state
struct ContentViewEmpty: View {
    @State private var accounts: [OtpModel] = []
    @State var addingAccount = false
    @State var deletingAccount: OtpModel?
    @State var showCopiedToast = false
    @State var search = ""
    @State private var showingErrorAlert = false
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationStack {
            ZStack {
                VStack {
                    GeometryReader { geometry in
                        ScrollView {
                            ZStack {
                                // Empty state - properly centered
                                VStack(spacing: 20) {
                                    Image(systemName: "lock.shield")
                                        .font(.system(size: 60))
                                        .foregroundColor(.secondary)
                                    VStack(spacing: 8) {
                                        Text("No TOTP accounts")
                                            .font(.title2)
                                            .fontWeight(.semibold)
                                        Text("Add your first account to get started")
                                            .font(.body)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                            }
                        }
                        .refreshable {
                            // Mock refresh action
                        }
                    }
                }
                
                // Floating Action Button (iOS only)
                #if os(iOS)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            self.addingAccount = true
                        }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.4, green: 0.5, blue: 1.0),
                                            Color(red: 0.6, green: 0.4, blue: 0.9)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 30)
                    }
                }
                #endif
            }
            .navigationTitle("TOTP Passwords")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }
}

// Mock view with sample data
struct ContentViewWithSampleData: View {
    @State private var accounts: [MockOtpModel] = [
        MockOtpModel(id: "1", name: "john.doe@gmail.com", issuer: "Google", currentCode: "123456"),
        MockOtpModel(id: "2", name: "GitHub", issuer: "GitHub", currentCode: "789012"),
        MockOtpModel(id: "3", name: "AWS Console", issuer: "Amazon", currentCode: "345678"),
        MockOtpModel(id: "4", name: "work@company.com", issuer: "Microsoft", currentCode: "901234"),
        MockOtpModel(id: "5", name: "Discord", issuer: "Discord", currentCode: "567890")
    ]
    @State var addingAccount = false
    @State var editingAccount: MockOtpModel?
    @State var deletingAccount: MockOtpModel?
    @State var showCopiedToast = false
    @State var search = ""
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        NavigationStack {
            ZStack {
                VStack {
                    GeometryReader { geometry in
                        ScrollView {
                            ZStack {
                                VStack {
                                    let searchField = self.search.trimmingCharacters(
                                        in: .whitespacesAndNewlines)
                                    LazyVGrid(
                                        columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: geometry.size.width > 768 ? 3 : 1),
                                        alignment: .center,
                                        spacing: 12
                                    ) {
                                        ForEach(accounts) { account in
                                            MockTotpView(
                                                otp: account,
                                                cutoff: geometry.size.width,
                                                deleting: $deletingAccount,
                                                editing: $editingAccount,
                                                toast: $showCopiedToast
                                            )
                                        }
                                    }
                                    .padding(.top)
                                    .padding(.horizontal, geometry.size.width > 768 ? 40 : 20)
                                    .frame(minWidth: geometry.size.width, maxWidth: geometry.size.width)

                                    Spacer()
                                        .frame(height: 20)
                                }
                            }
                        }
                        .refreshable {
                            // Mock refresh action
                        }
                        
                        // Toast message overlay
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Text("Code copied to clipboard")
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .background(
                                        .regularMaterial,
                                        in: RoundedRectangle(cornerRadius: 12))
                                Spacer()
                            }
                            .opacity(self.showCopiedToast ? 0.9 : 0.0)
                            .allowsHitTesting(false)
                            .padding()
                        }
                    }
                }
                
                // Floating Action Button (iOS only)
                #if os(iOS)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: {
                            self.addingAccount = true
                        }) {
                            Image(systemName: "plus")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            Color(red: 0.4, green: 0.5, blue: 1.0),
                                            Color(red: 0.6, green: 0.4, blue: 0.9)
                                        ]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 30)
                    }
                }
                #endif
            }
            .navigationTitle("TOTP Passwords")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }
}

// Mock data models for preview
struct MockOtpModel: Identifiable {
    let id: String
    let name: String
    let issuer: String
    let currentCode: String
}

// Mock TOTP view for preview
struct MockTotpView: View {
    let otp: MockOtpModel
    let cutoff: CGFloat
    @Binding var deleting: MockOtpModel?
    @Binding var editing: MockOtpModel?
    @Binding var toast: Bool
    @State private var offset: CGFloat = 0.0
    @State private var showingActions = false
    
    var body: some View {
        ZStack {
            // Background action buttons
            HStack {
                Spacer()
                
                // Edit button
                Button(action: {
                    withAnimation(.spring()) {
                        self.offset = 0
                        self.showingActions = false
                    }
                    // Mock edit action
                }) {
                    Image(systemName: "pencil")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.blue)
                }
                
                // Delete button
                Button(action: {
                    withAnimation(.spring()) {
                        self.offset = 0
                        self.showingActions = false
                    }
                    // Mock delete action
                }) {
                    Image(systemName: "trash")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(width: 60, height: 60)
                        .background(Color.red)
                }
            }
            .opacity(showingActions ? 1 : 0)
            
            // Main card content
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(otp.issuer)
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text(otp.name)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 12, height: 12)
                }
                
                HStack {
                    Text(otp.currentCode)
                        .font(.title)
                        .fontWeight(.bold)
                        .tracking(2)
                    Spacer()
                    ProgressView(value: 0.7)
                        .progressViewStyle(CircularProgressViewStyle())
                        .frame(width: 24, height: 24)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .offset(x: self.offset)
            .gesture(
                DragGesture(minimumDistance: 20, coordinateSpace: .local)
                    .onChanged { value in
                        // Only allow left swipe (negative translation)
                        if value.translation.width < 0 {
                            self.offset = max(value.translation.width, -120) // Limit to -120 points
                            self.showingActions = self.offset < -60
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring()) {
                            if value.translation.width < -60 {
                                // Show actions
                                self.offset = -120
                                self.showingActions = true
                            } else {
                                // Snap back
                                self.offset = 0
                                self.showingActions = false
                            }
                        }
                    }
            )
            .onTapGesture {
                if showingActions {
                    // Hide actions if they're showing
                    withAnimation(.spring()) {
                        self.offset = 0
                        self.showingActions = false
                    }
                } else {
                    // Mock copy action
                    toast = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        toast = false
                    }
                }
            }
        }
        .clipped()
    }
}
