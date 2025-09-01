import SwiftUI
import Foundation
import ZIPFoundation
import AuthenticationServices
import UniformTypeIdentifiers
import Darwin

// MARK: - Java Native Integration Headers
@_silgen_name("JNI_GetDefaultJavaVMInitArgs")
public func JNI_GetDefaultJavaVMInitArgs(_ args: UnsafeMutablePointer<JavaVMInitArgs>) -> jint

@_silgen_name("JNI_CreateJavaVM")
public func JNI_CreateJavaVM(
    pvm: UnsafeMutablePointer<UnsafeMutablePointer<JavaVM>?>?,
    penv: UnsafeMutablePointer<UnsafeMutablePointer<JNIEnv>?>?,
    args: UnsafeMutablePointer<JavaVMInitArgs>?
) -> jint

@_silgen_name("JNI_GetCreatedJavaVMs")
public func JNI_GetCreatedJavaVMs(
    vmBuf: UnsafeMutablePointer<UnsafeMutablePointer<JavaVM>?>?,
    bufLen: jsize,
    nVMs: UnsafeMutablePointer<jsize>?
) -> jint

// MARK: - Dynamic Loader Integration
@_silgen_name("DL_loadLibrary")
public func DL_loadLibrary(_ path: UnsafePointer<CChar>) -> UnsafeMutableRawPointer?

@_silgen_name("DL_getSymbol")
public func DL_getSymbol(_ handle: UnsafeMutableRawPointer?, _ symbol: UnsafePointer<CChar>) -> UnsafeMutableRawPointer?

// MARK: - JVM Wrapper Implementation
final class JVMHost {
    private static var vm: UnsafeMutablePointer<JavaVM>?
    private static var env: UnsafeMutablePointer<JNIEnv>?
    private static var isInitialized = false

    static func initialize() throws {
        guard !isInitialized else { return }

        guard let libHandle = DL_loadLibrary("libjava.a") else {
            throw NSError(domain: "JavaRuntime", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load libjava.a"])
        }

        guard let _ = DL_getSymbol(libHandle, "JRE_GetMemoryAPI"),
              let _ = DL_getSymbol(libHandle, "JNI_LoadDynamicCode") else {
            throw NSError(domain: "JavaRuntime", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Missing required symbols"])
        }

        var args = JavaVMInitArgs()
        args.version = JNI_VERSION_1_8
        args.nOptions = 0
        args.options = nil
        args.ignoreUnrecognized = JNI_TRUE

        var vm: UnsafeMutablePointer<JavaVM>?
        var env: UnsafeMutablePointer<JNIEnv>?

        let result = JNI_CreateJavaVM(&vm, &env, &args)
        guard result == JNI_OK else {
            throw NSError(domain: "JavaRuntime", code: Int(result),
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create Java VM"])
        }

        self.vm = vm
        self.env = env
        self.isInitialized = true

        // Initialize memory manager
        initializeMemoryManager()
    }

    private static func initializeMemoryManager() {
        guard let memorySymbol = DL_getSymbol(nil, "JRE_GetMemoryAPI") else { return }
        let memoryAPI = unsafeBitCast(memorySymbol, to: (@convention(c) () -> UnsafeRawPointer).self)()
        print("Memory API initialized at: \(memoryAPI)")
    }

    import Foundation

// MARK: - Dynamic Loader
@_silgen_name("DL_loadLibrary")
public func DL_loadLibrary(_ path: UnsafePointer<CChar>) -> UnsafeMutableRawPointer?

@_silgen_name("DL_getSymbol")
public func DL_getSymbol(_ handle: UnsafeMutableRawPointer?, _ symbol: UnsafePointer<CChar>) -> UnsafeMutableRawPointer?

final class RoboVMHost {
    private static var handle: UnsafeMutableRawPointer?

    /// 1️⃣ Load RoboVM library / static lib
    static func loadRoboVMLibrary(at path: String) throws {
        guard handle == nil else { return }
        guard let libHandle = DL_loadLibrary(path) else {
            throw NSError(domain: "RoboVMHost", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to load library at \(path)"])
        }
        handle = libHandle
        print("RoboVM library loaded: \(path)")
    }

    /// 2️⃣ Compile .jar → native executable
    static func compileJar(at jarPath: String, outputPath: String) throws {
        guard let handle = handle else {
            throw NSError(domain: "RoboVMHost", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "RoboVM library not loaded"])
        }

        guard let compileSymbol = DL_getSymbol(handle, "RoboVM_CompileJar") else {
            throw NSError(domain: "RoboVMHost", code: -3,
                          userInfo: [NSLocalizedDescriptionKey: "Symbol 'RoboVM_CompileJar' not found"])
        }

        typealias CompileFunc = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32
        let compileFunc = unsafeBitCast(compileSymbol, to: CompileFunc.self)

        let result = compileFunc(jarPath, outputPath)
        guard result == 0 else {
            throw NSError(domain: "RoboVMHost", code: Int(result),
                          userInfo: [NSLocalizedDescriptionKey: "Failed to compile jar"])
        }

        print("Jar compiled to native executable: \(outputPath)")
    }

    /// 3️⃣ Launch Minecraft directly via RoboVM AOT
    static func launchMinecraft(version: MinecraftVersion, account: MinecraftAccount) throws {
        // 3a️⃣ Paths
        let gameDir = version.path.path
        let jarPath = "\(gameDir)/client.jar"
        let symbolName = "MinecraftMain" // entry symbol exported by RoboVM AOT
        let args = [
            "-Djava.library.path=\(gameDir)/natives",
            "-Dminecraft.client.jar=\(jarPath)",
            "-Dminecraft.username=\(account.username)",
            "-Dminecraft.uuid=\(account.uuid)",
            "-Dminecraft.accessToken=\(account.accessToken)",
            "-Xmx2G"
        ]

        // 3b️⃣ Ensure library is loaded
        guard handle != nil else {
            throw NSError(domain: "RoboVMHost", code: -4,
                          userInfo: [NSLocalizedDescriptionKey: "RoboVM library not loaded"])
        }

        // 3c️⃣ Compile the jar first (AOT)
        let outputExe = "\(gameDir)/MinecraftAOT"
        try compileJar(at: jarPath, outputPath: outputExe)

        // 3d️⃣ Launch native entry point
        try launchExecutable(named: symbolName, args: args)
    }

    /// 4️⃣ Generic launcher for any executable (used internally)
    static func launchExecutable(named symbol: String, args: [String]) throws {
        guard let handle = handle else {
            throw NSError(domain: "RoboVMHost", code: -5,
                          userInfo: [NSLocalizedDescriptionKey: "RoboVM library not loaded"])
        }

        guard let mainSymbol = DL_getSymbol(handle, symbol) else {
            throw NSError(domain: "RoboVMHost", code: -6,
                          userInfo: [NSLocalizedDescriptionKey: "Symbol \(symbol) not found"])
        }

        typealias MainFunc = @convention(c) (Int32, UnsafePointer<UnsafePointer<CChar>?>?) -> Void
        let mainFunc = unsafeBitCast(mainSymbol, to: MainFunc.self)

        let cStrings = args.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }

        cStrings.withUnsafeBufferPointer { buffer in
            mainFunc(Int32(buffer.count), buffer.baseAddress)
        }
    }
}
// MARK: - Minecraft Data Models
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

// MARK: - Complete MinecraftManager Implementation
final class MinecraftManager: ObservableObject {
    @Published var installedVersions = [MinecraftVersion]()
    @Published var availableVersions = [String]()
    @Published var modLoaderVersions = [ModLoaderVersion]()
    @Published var account: MinecraftAccount?
    @Published var isWorking = false
    @Published var showFileBrowser = false
    @Published var selectedVersionForInstall = ""
    @Published var selectedModLoader: ModLoaderType?
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
        
        do {
            try JVMHost.initialize()
            try JVMHost.launchMinecraft(version: version, account: account)
        } catch {
            showAlert(title: "Launch Error", message: error.localizedDescription)
        }
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

// MARK: - Supporting Types
struct FabricVersion: Decodable {
    struct Loader: Decodable {
        let version: String
    }
    let loader: Loader
}

struct ForgeMetadata: Decodable {
    let versions: [String]
}

// MARK: - Auth Handler
class AuthHandler: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}

// MARK: - Content View
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
        // ... (keep original login implementation)
    }
}

// MARK: - Version Installer View
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

// MARK: - Version Row
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

// MARK: - Document Browser
struct DocumentBrowserView: UIViewControllerRepresentable {
    let directoryURL: URL
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        controller.directoryURL = directoryURL
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}

// MARK: - App Entry
@main
struct MinecraftManagerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
