import SwiftUI
import Foundation
import ZIPFoundation
import AuthenticationServices
import UniformTypeIdentifiers
import WebKit

struct CheerpJWebView: UIViewRepresentable {
    let version: MinecraftVersion
    let account: MinecraftAccount
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.configuration.preferences.javaScriptEnabled = true
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let htmlString = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Minecraft with CheerpJ</title>
            <script src="https://cjrtnc.leaningtech.com/3.0/loader.js"></script>
            <style>
                body { margin: 0; padding: 0; background-color: #000; }
                #loading {
                    color: white;
                    font-family: Arial;
                    text-align: center;
                    margin-top: 50vh;
                    transform: translateY(-50%);
                }
            </style>
        </head>
        <body>
            <div id="loading">Loading Minecraft...</div>
            <script>
                cheerpjInit({
                    minecraftVersion: "\(version.id)",
                    username: "\(account.username)",
                    uuid: "\(account.uuid)",
                    accessToken: "\(account.accessToken)",
                    gameDir: "\(version.path.path)"
                });
                
                function cheerpjInit(config) {
                    cheerpjInitRuntime({
                        javaProperties: [
                            `-Dminecraft.client.jar=${config.gameDir}/client.jar`,
                            `-Dminecraft.username=${config.username}`,
                            `-Dminecraft.uuid=${config.uuid}`,
                            `-Dminecraft.accessToken=${config.accessToken}`,
                            `-Dminecraft.version=${config.minecraftVersion}`,
                            `-Xmx2G`
                        ],
                        classpath: [
                            `${config.gameDir}/client.jar`,
                            `${config.gameDir}/libraries/*`
                        ],
                        mainClass: "net.minecraft.client.main.Main",
                        onLoad: function() {
                            document.getElementById('loading').innerHTML = 'Starting Minecraft...';
                        },
                        onError: function(error) {
                            document.getElementById('loading').innerHTML = 'Error: ' + error;
                        }
                    });
                }
            </script>
        </body>
        </html>
        """
        
        uiView.loadHTMLString(htmlString, baseURL: URL(string: "https://cheerpj-demo.leaningtech.com/"))
    }
}

struct MinecraftVersion: Identifiable {
    let id: String
    let type: String
    var path: URL
    var mods: [Mod]
    var isInstalled: Bool
    var modLoader: ModLoaderType?
}

struct Mod: Identifiable {
    let id = UUID()
    let name: String
    let version: String
    let filePath: URL
}

struct ModLoaderVersion: Identifiable {
    let id: String
    let name: String
    let compatible: [String]
}

enum ModLoaderType: String, CaseIterable {
    case forge = "Forge"
    case fabric = "Fabric"
    case quilt = "Quilt"
}

struct MinecraftAccount {
    let username: String
    let uuid: String
    let accessToken: String
}

struct FabricVersion: Decodable {
    struct Loader: Decodable {
        let version: String
    }
    let loader: Loader
}

struct ForgeMetadata: Decodable {
    let versions: [String]
}

final class MinecraftManager: ObservableObject {
    @Published var installedVersions = [MinecraftVersion]()
    @Published var availableVersions = [String]()
    @Published var modLoaderVersions = [ModLoaderVersion]()
    @Published var account: MinecraftAccount?
    @Published var isWorking = false
    @Published var showFileBrowser = false
    @Published var selectedVersionForInstall = ""
    @Published var selectedModLoader: ModLoaderType?
    @Published var showCheerpJView = false
    @Published var selectedVersionForLaunch: MinecraftVersion?
    
    private let baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Minecraft")
    let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    
    init() {
        setupDirectories()
        loadInstalledVersions()
        fetchAvailableVersions()
    }
    
    private func setupDirectories() {
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
    }
    
    func loadInstalledVersions() {
        installedVersions = []
        let versionDirs = (try? FileManager.default.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil)) ?? []
        
        for dir in versionDirs {
            let modsDir = dir.appendingPathComponent("mods")
            let modFiles = (try? FileManager.default.contentsOfDirectory(at: modsDir, includingPropertiesForKeys: nil)) ?? []
            
            var mods = [Mod]()
            for modFile in modFiles {
                let name = modFile.deletingPathExtension().lastPathComponent
                mods.append(Mod(name: name, version: "1.0", filePath: modFile))
            }
            
            let versionName = dir.lastPathComponent
            let components = versionName.components(separatedBy: "_")
            let mcVersion = components.first ?? versionName
            let loaderType = components.count > 1 ? ModLoaderType(rawValue: components[1]) : nil
            
            installedVersions.append(MinecraftVersion(
                id: versionName,
                type: "release",
                path: dir,
                mods: mods,
                isInstalled: true,
                modLoader: loaderType
            ))
        }
    }
    
    func fetchAvailableVersions() {
        guard let url = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest.json") else { return }
        
        isWorking = true
        URLSession.shared.dataTask(with: url) { data, _, _ in
            defer { DispatchQueue.main.async { self.isWorking = false } }
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let versions = json["versions"] as? [[String: Any]] else { return }
            
            DispatchQueue.main.async {
                self.availableVersions = versions.compactMap { $0["id"] as? String }
            }
        }.resume()
    }
    
    func fetchModLoaderVersions(for mcVersion: String) {
        isWorking = true
        
        DispatchQueue.global().async {
            let group = DispatchGroup()
            var loaders = [ModLoaderVersion]()
            
            group.enter()
            if let url = URL(string: "https://meta.fabricmc.net/v2/versions/loader/\(mcVersion)") {
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    if let data = data,
                       let versions = try? JSONDecoder().decode([FabricVersion].self, from: data) {
                        versions.forEach {
                            loaders.append(ModLoaderVersion(
                                id: "fabric_\($0.loader.version)",
                                name: "Fabric \($0.loader.version)",
                                compatible: [$0.loader.version]
                            ))
                        }
                    }
                    group.leave()
                }.resume()
            } else {
                group.leave()
            }
            
            group.enter()
            if let url = URL(string: "https://files.minecraftforge.net/net/minecraftforge/forge/maven-metadata.json") {
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    if let data = data,
                       let metadata = try? JSONDecoder().decode(ForgeMetadata.self, from: data) {
                        metadata.versions
                            .filter { $0.contains(mcVersion) }
                            .forEach {
                                loaders.append(ModLoaderVersion(
                                    id: "forge_\($0)",
                                    name: "Forge \($0)",
                                    compatible: [$0]
                                ))
                            }
                    }
                    group.leave()
                }.resume()
            } else {
                group.leave()
            }
            
            group.notify(queue: .main) {
                self.modLoaderVersions = loaders
                self.isWorking = false
            }
        }
    }
    
    func installVersion(version: String, loader: ModLoaderType?) {
        isWorking = true
        
        DispatchQueue.global().async {
            let versionName = loader == nil ? version : "\(version)_\(loader!.rawValue.lowercased())"
            let versionURL = self.baseURL.appendingPathComponent(versionName)
            
            do {
                try FileManager.default.createDirectory(at: versionURL, withIntermediateDirectories: true, attributes: nil)
                try FileManager.default.createDirectory(at: versionURL.appendingPathComponent("mods"), withIntermediateDirectories: true, attributes: nil)
                
                if let loader = loader {
                    switch loader {
                    case .fabric:
                        self.installFabricLoader(version: version, directory: versionURL)
                    case .forge:
                        self.installForgeLoader(version: version, directory: versionURL)
                    case .quilt:
                        break
                    }
                } else {
                    self.downloadMinecraftClient(version: version, directory: versionURL)
                }
                
                DispatchQueue.main.async {
                    self.loadInstalledVersions()
                    self.isWorking = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                }
            }
        }
    }
    
    private func installFabricLoader(version: String, directory: URL) {
        guard let url = URL(string: "https://meta.fabricmc.net/v2/versions/loader/\(version)") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let versions = try? JSONDecoder().decode([FabricVersion].self, from: data),
                  let latest = versions.first,
                  let installerURL = URL(string: "https://maven.fabricmc.net/net/fabricmc/fabric-installer/\(latest.loader.version)/fabric-installer-\(latest.loader.version).jar") else { return }
            
            self.downloadAndSaveInstaller(url: installerURL, directory: directory)
        }.resume()
    }
    
    private func installForgeLoader(version: String, directory: URL) {
        guard let url = URL(string: "https://files.minecraftforge.net/net/minecraftforge/forge/maven-metadata.json") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let metadata = try? JSONDecoder().decode(ForgeMetadata.self, from: data),
                  let forgeVersion = metadata.versions.first(where: { $0.contains(version) }),
                  let installerURL = URL(string: "https://files.minecraftforge.net/net/minecraftforge/forge/\(forgeVersion)/forge-\(forgeVersion)-installer.jar") else { return }
            
            self.downloadAndSaveInstaller(url: installerURL, directory: directory)
        }.resume()
    }
    
    private func downloadAndSaveInstaller(url: URL, directory: URL) {
        URLSession.shared.downloadTask(with: url) { tempURL, _, _ in
            guard let tempURL = tempURL else { return }
            
            do {
                let installerURL = directory.appendingPathComponent("installer.jar")
                try FileManager.default.moveItem(at: tempURL, to: installerURL)
            } catch {
                print(error)
            }
        }.resume()
    }
    
    private func downloadMinecraftClient(version: String, directory: URL) {
        guard let url = URL(string: "https://launchermeta.mojang.com/mc/game/version_manifest.json") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let versions = json["versions"] as? [[String: Any]],
                  let versionInfo = versions.first(where: { ($0["id"] as? String) == version }),
                  let versionURLString = versionInfo["url"] as? String,
                  let versionURL = URL(string: versionURLString) else { return }
            
            URLSession.shared.dataTask(with: versionURL) { data, _, _ in
                guard let data = data,
                      let versionJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let downloads = versionJson["downloads"] as? [String: Any],
                      let client = downloads["client"] as? [String: Any],
                      let clientURLString = client["url"] as? String,
                      let clientURL = URL(string: clientURLString) else { return }
                
                URLSession.shared.downloadTask(with: clientURL) { tempURL, _, _ in
                    guard let tempURL = tempURL else { return }
                    
                    do {
                        let clientJar = directory.appendingPathComponent("client.jar")
                        try FileManager.default.moveItem(at: tempURL, to: clientJar)
                    } catch {
                        print(error)
                    }
                }.resume()
            }.resume()
        }.resume()
    }
    
    func importModpack(_ fileURL: URL) {
        isWorking = true
        
        DispatchQueue.global().async {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            
            do {
                try FileManager.default.unzipItem(at: fileURL, to: tempDir)
                
                guard let manifestFile = FileManager.default.contents(atPath: tempDir.appendingPathComponent("manifest.json").path),
                      let manifest = try? JSONSerialization.jsonObject(with: manifestFile) as? [String: Any],
                      let minecraftInfo = manifest["minecraft"] as? [String: Any],
                      let version = minecraftInfo["version"] as? String else {
                    DispatchQueue.main.async {
                        self.isWorking = false
                    }
                    return
                }
                
                let versionName = "\(version)_modpack"
                let versionURL = self.baseURL.appendingPathComponent(versionName)
                try? FileManager.default.removeItem(at: versionURL)
                try? FileManager.default.createDirectory(at: versionURL, withIntermediateDirectories: true, attributes: nil)
                
                let contents = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
                for item in contents {
                    let source = tempDir.appendingPathComponent(item)
                    let destination = versionURL.appendingPathComponent(item)
                    try FileManager.default.copyItem(at: source, to: destination)
                }
                
                DispatchQueue.main.async {
                    self.loadInstalledVersions()
                    self.isWorking = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isWorking = false
                }
            }
        }
    }
    
    func launchVersion(_ version: MinecraftVersion) {
        guard let account = account else {
            showAlert(title: "Error", message: "Please login first")
            return
        }
        
        selectedVersionForLaunch = version
        showCheerpJView = true
    }
    
    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootViewController = windowScene.windows.first?.rootViewController {
                rootViewController.present(alert, animated: true)
            }
        }
    }
    
    func openAppDirectory() {
        showFileBrowser = true
    }
}

class AuthHandler: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}

struct ContentView: View {
    @StateObject private var manager = MinecraftManager()
    @State private var showingImporter = false
    @State private var showingInstaller = false
    @State private var isAuthenticating = false
    @State private var authError: String?
    
    var body: some View {
        NavigationView {
            List {
                Section("Installed Versions") {
                    ForEach(manager.installedVersions) { version in
                        VersionRow(version: version) {
                            manager.launchVersion(version)
                        }
                    }
                }
                
                Section("Actions") {
                    Button("Install New Version") {
                        showingInstaller = true
                    }
                    
                    Button("Import Modpack") {
                        showingImporter = true
                    }
                    
                    Button("Open App Directory") {
                        manager.openAppDirectory()
                    }
                    
                    if manager.account == nil {
                        Button {
                            login()
                        } label: {
                            HStack {
                                Image(systemName: "xbox.logo")
                                Text("Login with Microsoft")
                            }
                        }
                        .disabled(isAuthenticating)
                    } else {
                        Button("Logout") {
                            manager.account = nil
                        }
                    }
                }
            }
            .navigationTitle("Minecraft Manager")
            .sheet(isPresented: $showingInstaller) {
                VersionInstallerView(manager: manager)
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.zip]) { result in
                if case .success(let url) = result {
                    manager.importModpack(url)
                }
            }
            .sheet(isPresented: $manager.showFileBrowser) {
                DocumentBrowserView(directoryURL: manager.documentsURL)
            }
            .fullScreenCover(isPresented: $manager.showCheerpJView) {
                if let version = manager.selectedVersionForLaunch, let account = manager.account {
                    ZStack {
                        CheerpJWebView(version: version, account: account)
                            .edgesIgnoringSafeArea(.all)
                        
                        Button(action: {
                            manager.showCheerpJView = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.white)
                                .padding()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
            }
            .overlay {
                if manager.isWorking || isAuthenticating {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.5))
                }
            }
            .alert("Authentication Error", isPresented: .constant(authError != nil)) {
                Button("OK") { authError = nil }
            } message: {
                Text(authError ?? "")
            }
        }
    }
    
    private func login() {
        isAuthenticating = true
        authError = nil
        
        let authURL = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize?client_id=00000000402b5328&response_type=code&scope=XboxLive.signin%20offline_access&redirect_uri=msauth.com.yourdomain.minecraftmanager://auth")!
        
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "msauth.com.yourdomain.minecraftmanager"
        ) { callbackURL, error in
            DispatchQueue.main.async {
                isAuthenticating = false
                
                if let error = error {
                    authError = error.localizedDescription
                    return
                }
                
                guard let callbackURL = callbackURL,
                      let code = URLComponents(string: callbackURL.absoluteString)?.queryItems?.first(where: { $0.name == "code" })?.value else {
                    authError = "Failed to get authentication code"
                    return
                }
                
                authenticateWithCode(code: code)
            }
        }
        
        session.presentationContextProvider = AuthHandler()
        session.prefersEphemeralWebBrowserSession = true
        session.start()
    }
    
    private func authenticateWithCode(code: String) {
        isAuthenticating = true
        
        let tokenURL = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": "00000000402b5328",
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": "msauth.com.yourdomain.minecraftmanager://auth",
            "scope": "XboxLive.signin offline_access"
        ].map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        
        request.httpBody = body.data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    isAuthenticating = false
                    authError = error.localizedDescription
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let accessToken = json["access_token"] as? String else {
                    isAuthenticating = false
                    authError = "Failed to get access token"
                    return
                }
                
                getXboxLiveToken(accessToken: accessToken)
            }
        }.resume()
    }
    
    private func getXboxLiveToken(accessToken: String) {
        let url = URL(string: "https://user.auth.xboxlive.com/user/authenticate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "Properties": [
                "AuthMethod": "RPS",
                "SiteName": "user.auth.xboxlive.com",
                "RpsTicket": "d=\(accessToken)"
            ],
            "RelyingParty": "http://auth.xboxlive.com",
            "TokenType": "JWT"
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    isAuthenticating = false
                    authError = error.localizedDescription
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let token = json["Token"] as? String,
                      let displayClaims = json["DisplayClaims"] as? [String: Any],
                      let xui = displayClaims["xui"] as? [[String: Any]],
                      let uhs = xui.first?["uhs"] as? String else {
                    isAuthenticating = false
                    authError = "Failed to get Xbox Live token"
                    return
                }
                
                getXSTSToken(xboxToken: token, userHash: uhs)
            }
        }.resume()
    }
    
    private func getXSTSToken(xboxToken: String, userHash: String) {
        let url = URL(string: "https://xsts.auth.xboxlive.com/xsts/authorize")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "Properties": [
                "SandboxId": "RETAIL",
                "UserTokens": [xboxToken]
            ],
            "RelyingParty": "rp://api.minecraftservices.com/",
            "TokenType": "JWT"
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    isAuthenticating = false
                    authError = error.localizedDescription
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let xstsToken = json["Token"] as? String else {
                    isAuthenticating = false
                    authError = "Failed to get XSTS token"
                    return
                }
                
                getMinecraftToken(xstsToken: xstsToken, userHash: userHash)
            }
        }.resume()
    }
    
    private func getMinecraftToken(xstsToken: String, userHash: String) {
        let url = URL(string: "https://api.minecraftservices.com/authentication/login_with_xbox")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "identityToken": "XBL3.0 x=\(userHash);\(xstsToken)"
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    isAuthenticating = false
                    authError = error.localizedDescription
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let accessToken = json["access_token"] as? String else {
                    isAuthenticating = false
                    authError = "Failed to get Minecraft token"
                    return
                }
                
                getMinecraftProfile(accessToken: accessToken)
            }
        }.resume()
    }
    
    private func getMinecraftProfile(accessToken: String) {
        let url = URL(string: "https://api.minecraftservices.com/minecraft/profile")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isAuthenticating = false
                
                if let error = error {
                    authError = error.localizedDescription
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let uuid = json["id"] as? String,
                      let username = json["name"] as? String else {
                    authError = "Failed to get Minecraft profile"
                    return
                }
                
                manager.account = MinecraftAccount(
                    username: username,
                    uuid: uuid,
                    accessToken: accessToken
                )
            }
        }.resume()
    }
}

struct VersionInstallerView: View {
    @ObservedObject var manager: MinecraftManager
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            Form {
                Section("Minecraft Version") {
                    Picker("Select Version", selection: $manager.selectedVersionForInstall) {
                        ForEach(manager.availableVersions, id: \.self) { version in
                            Text(version).tag(version)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: manager.selectedVersionForInstall) { _ in
                        if !manager.selectedVersionForInstall.isEmpty {
                            manager.fetchModLoaderVersions(for: manager.selectedVersionForInstall)
                        }
                    }
                }
                
                Section("Mod Loader (Optional)") {
                    Picker("Select Loader Type", selection: $manager.selectedModLoader) {
                        Text("None").tag(nil as ModLoaderType?)
                        ForEach(ModLoaderType.allCases, id: \.self) { loader in
                            Text(loader.rawValue).tag(loader as ModLoaderType?)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    if !manager.modLoaderVersions.isEmpty && manager.selectedModLoader != nil {
                        Picker("Loader Version", selection: .constant(0)) {
                            ForEach(manager.modLoaderVersions) { version in
                                Text(version.name).tag(version.id)
                            }
                        }
                    }
                }
                
                Section {
                    Button("Install") {
                        manager.installVersion(
                            version: manager.selectedVersionForInstall,
                            loader: manager.selectedModLoader
                        )
                        presentationMode.wrappedValue.dismiss()
                    }
                    .disabled(manager.selectedVersionForInstall.isEmpty)
                }
            }
            .navigationTitle("Install Version")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

struct VersionRow: View {
    let version: MinecraftVersion
    let action: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(version.id)
                    .font(.headline)
                
                if let loader = version.modLoader {
                    Text(loader.rawValue)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text("\(version.mods.count) mods")
                    .font(.caption)
            }
            
            Spacer()
            
            Button("Launch", action: action)
                .buttonStyle(.bordered)
        }
    }
}

struct DocumentBrowserView: UIViewControllerRepresentable {
    let directoryURL: URL
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        controller.directoryURL = directoryURL
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

@main
struct MinecraftManagerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
