// Launcher settings, validation and persistence. Shared by the iOS UI, the Mac app's settings window (dm/mac/Launcher.swift) and the native storage regression test.
import Foundation
import Combine

// The launcher's text is English (dm/games/settings.tsv, and the fixed lines on the screen); this maps it for a Chinese player.
// A string with no mapping is shown as it came, so a new setting or a game's own label never hides or crashes. The iOS screen is
// Chinese when DM_LAUNCHER_LANG=zh forces it, or when Info.plist's DMLanguage (the game language the app was packed with) or the
// system's first preferred language starts with zh; DM_LAUNCHER_LANG=en keeps English. The Mac window (which shares LauncherRow.swift)
// stays English unless the variable forces it: its own window text is not mapped.
enum LauncherText {
    static let chinese: Bool = {
        let forced = ProcessInfo.processInfo.environment["DM_LAUNCHER_LANG"]?.lowercased() ?? ""
        if forced.hasPrefix("zh") { return true }
        if forced.hasPrefix("en") { return false }
        #if os(iOS)
        if let lang = Bundle.main.object(forInfoDictionaryKey: "DMLanguage") as? String, lang.lowercased().hasPrefix("zh") { return true }
        if let lang = Locale.preferredLanguages.first?.lowercased(), lang.hasPrefix("zh") { return true }
        #endif
        return false
    }()

    private static let map: [String: String] = [
        // Headings
        "Game": "游戏",
        "Controls": "操作",
        "Performance": "性能",
        // Setting labels
        "Frame rate": "帧率",
        "Frame generation": "帧生成",
        "Dynamic resolution": "动态分辨率",
        "Render scale": "渲染缩放",
        "Console mode": "主机模式",
        "Upscaling": "画面放大",
        "Game's upscaler": "游戏自带放大",
        "Game language": "游戏语言",
        "Display mode": "显示模式",
        "Picture": "画面",
        "Frame-rate counter": "帧率计数器",
        "Touch feedback": "触摸反馈",
        "Game rumble": "游戏震动",
        "Rumble strength": "震动强度",
        "Rumble cutoff": "震动截止阈值",
        "Picture shape": "画面比例",
        "Frame buffering": "帧缓冲",
        "Metal 4 pipelines": "Metal 4 管线",
        "Pipeline prebuild": "管线预构建",
        "Encode thread": "编码线程",
        "Hold frames when late": "延迟时保持帧",
        "Performance HUD": "性能 HUD",
        // Notes
        "Experimental engine timing target; actual performance and game speed need device testing.":
            "实验性引擎时序目标；实际性能与游戏速度需在设备上测试。",
        "Removes the 30 fps limit with variable game timing. Actual frame rate depends on device performance.":
            "解除 30 fps 限制，游戏时序随之变化。实际帧率取决于设备性能。",
        "Generates one intermediate picture per real frame. Uses image optical flow, not the MetalFX frame interpolator. Real target is at most 60 for 120 Hz output; fast HUD motion may show artifacts.":
            "每实际帧生成一张中间画面。使用图像光流，而非 MetalFX 帧插值器。120 Hz 输出时实际目标最高为 60；HUD 快速移动时可能出现画面瑕疵。",
        "Adjusts resolution between 70% and 100% under load. Turn off to keep full resolution for the selected console mode.":
            "负载较高时在 70% 到 100% 之间调整分辨率。关闭后按所选主机模式保持完整分辨率。",
        "Uses more GPU time and can increase heat.":
            "占用更多 GPU 时间，可能增加发热。",
        "Fill crops the game's 16:9 picture to cover the screen. Health bars, subtitles or maps near the edges can be cut off. A full-screen picture without cropping needs a patch for each game.":
            "填充会裁剪游戏的 16:9 画面以铺满屏幕。靠近边缘的血条、字幕或地图可能被裁掉。要在不裁剪的情况下全屏显示，需要为每个游戏单独制作补丁。",
        "Renders about a quarter more pixels: a little slower and warmer.":
            "多渲染约四分之一的像素：速度稍慢，发热略高。",
        "Up to one frame more display latency.":
            "显示延迟最多增加一帧。",
        "Keeps a pipeline archive; uses more memory.":
            "保留管线归档；占用更多内存。",
        "The first start waits a few minutes for it, once.":
            "首次启动需等待几分钟，仅一次。",
        "This game needs a dual-source shader variant before Metal 4 pipelines can be enabled.":
            "此游戏需要双源着色器变体，才能启用 Metal 4 管线。",
        "This game's files do not list its languages, so some of these may not be in the game. It may then show another one.":
            "此游戏的文件未列出支持的语言，因此其中一些可能并不存在；游戏可能会改用其他语言显示。",
        // Choice values
        "Off": "关闭",
        "On": "开启",
        "Docked": "底座模式",
        "Handheld": "掌机模式",
        "Standard": "标准",
        "Game's own": "游戏自带",
        "Window": "窗口",
        "Fullscreen": "全屏",
        "Fit": "适应",
        "Fill": "填充",
        "Original 30 fps": "原始 30 fps",
        "Optical flow (experimental)": "光流（实验性）",
        "iPhone Duo screen (1.43:1)": "iPhone Duo 屏幕（1.43:1）",
        "16:9 (Switch)": "16:9（Switch）",
        "Unavailable pending shader fix": "暂不可用（等待着色器修复）",
        // Game languages (dm/tools/nacp.py's names)
        "American English": "美式英语",
        "British English": "英式英语",
        "Japanese": "日语",
        "French": "法语",
        "German": "德语",
        "Latin American Spanish": "拉丁美洲西班牙语",
        "Spanish": "西班牙语",
        "Italian": "意大利语",
        "Dutch": "荷兰语",
        "Canadian French": "加拿大法语",
        "Portuguese": "葡萄牙语",
        "Russian": "俄语",
        "Korean": "韩语",
        "Traditional Chinese": "繁体中文",
        "Simplified Chinese": "简体中文",
        "Brazilian Portuguese": "巴西葡萄牙语",
        // The screen's fixed text (Launcher.swift, LauncherRow.swift)
        "Play": "开始游戏",
        "Version": "版本",
        "Reset to tested defaults": "恢复测试默认值",
        "Brings back all settings this game was tested with.":
            "恢复此游戏经过测试时的全部设置。",
        "Cloud saves": "云存档",
        "Choose a folder in iCloud Drive…": "在 iCloud 云盘中选择文件夹…",
        "Choose a different folder…": "选择其他文件夹…",
        "Turn off cloud saves": "关闭云存档",
        "Saved. The game uses this folder when you press Play.":
            "已保存。开始游戏时将使用此文件夹。",
        "That folder could not be remembered — try a different one.":
            "无法记住该文件夹，请换一个试试。",
        "Memory available": "可用内存",
        "Choose a folder in iCloud Drive, and the same one in the Mac app's Cloud saves. The save comes in when the game starts and goes out after each save; a save that is replaced is kept in save-backups.":
            "在 iCloud 云盘中选择一个文件夹，并在 Mac 应用的“云存档”中选择同一个文件夹。游戏启动时会取回存档，每次存档后会发送回去；被替换的存档会保留在 save-backups 中。",
        "The folder you chose before is no longer readable (the app was signed differently). Please choose it again.":
            "之前选择的文件夹已无法读取（应用签名已改变）。请重新选择。",
        "Set at launch": "启动时已设置",
        "Set by an env file": "由 env 文件设置",
    ]

    static func text(_ s: String) -> String { chinese ? (map[s] ?? s) : s }
}

struct Setting: Decodable, Identifiable {
    let env, kind, label, note, def: String
    let section: String?   // heading on the settings screen; absent in older bundles
    let needs: String?     // "<VAR>=<value>": a sub-setting, drawn only while that setting has that value
    let level: String?     // "basic": shown first (the Mac window's Basic settings); any other or none: Advanced settings. The iPhone keeps one list
    let base: Base?        // render scale: the 3D views' size at 1.0, docked and handheld, for the size in pixels (the Mac window)
    struct Base: Decodable { let docked, handheld: [Int] }
    let options: [[String]]?   // choice: [value, label]
    let min, max, step: Double?   // range
    let on, off: String?   // toggle: the values the variable takes (1 / 0 when not given)
    var id: String { env }
    var sectionTitle: String { section ?? "Game" }
    var basic: Bool { level == "basic" }
    var onValue: String { on ?? "1" }
    var offValue: String { off ?? "0" }
    func isDefault(_ v: String) -> Bool {   // a range compares as numbers (a slider writes 1.00 for 1.0)
        kind == "range" ? abs((Double(v) ?? .nan) - (Double(def) ?? .nan)) < 1e-6 : v == def
    }
    func accepts(_ v: String) -> Bool {   // a saved choice the game still offers
        switch kind {
        case "choice": return options?.contains { $0[0] == v } ?? false
        case "range":
            guard !v.contains(where: { $0 == "x" || $0 == "X" }), let n = Double(v), n.isFinite, let lo = min, let hi = max else { return false }   // no hex: launcher.c's check agrees
            return n >= lo && n <= hi
        case "toggle": return v == onValue || v == offValue
        default: return true
        }
    }
    enum CodingKeys: String, CodingKey { case env, kind, label, note, def = "default", section, needs, level, base, options, min, max, step, on, off }
}
struct SettingsFile: Decodable { let settings: [Setting] }

final class LauncherModel: ObservableObject {
    let settings: [Setting]
    let fixed: Set<String>      // set by an env file or by the launch environment: shown, not changed
    let fromLaunch: Set<String>   // of those, the ones the launch environment set (a front end's launch overrides, Xcode; DM_ENV_LAUNCH_KEYS from launcher.c or main.m)
    let ignoreSaved: Bool   // DM_SAVED_CHOICES=0: start from the defaults, and leave the saved choices as they are
    @Published var values: [String: String] = [:]

    private let defaults: UserDefaults

    init(_ settings: [Setting], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = settings
        let env = ProcessInfo.processInfo.environment
        fromLaunch = Set((env["DM_ENV_LAUNCH_KEYS"] ?? "").split(separator: " ").map(String.init))
        fixed = fromLaunch.union((env["DM_ENV_FILE_KEYS"] ?? "").split(separator: " ").map(String.init))
        ignoreSaved = env["DM_SAVED_CHOICES"] == "0"
        if ignoreSaved { fputs("launcher: saved choices ignored (DM_SAVED_CHOICES=0)\n", stderr) }
        for s in settings {
            if fixed.contains(s.env), let v = env[s.env] { values[s.env] = v; continue }
            let saved = ignoreSaved ? nil : defaults.object(forKey: "launcher." + s.env) as? String   // a string, as launcher.c reads it: not string(forKey:), which turns a number into one
            values[s.env] = saved.flatMap { s.accepts($0) ? $0 : nil } ?? s.def   // a saved choice the game no longer offers: its default
        }
    }

    var sections: [String] {
        settings.reduce(into: []) { if !$0.contains($1.sectionTitle) { $0.append($1.sectionTitle) } }
    }
    // A row with "needs" is a sub-setting of the row it names: drawn only while that setting has that value, so a
    // setting that cannot do anything is not offered (an upscaler's detail with the upscaler off, rumble strength
    // with rumble off). A row naming a setting this game does not have stays drawn, as it has nothing to hide behind
    func visible(_ s: Setting) -> Bool {
        guard let n = s.needs, let eq = n.firstIndex(of: "=") else { return true }
        let key = String(n[n.startIndex..<eq]), want = String(n[n.index(after: eq)...])
        guard let v = values[key] else { return true }
        return v == want
    }
    func rows(in section: String) -> [Setting] { settings.filter { $0.sectionTitle == section && visible($0) } }
    // The Mac window: Basic settings first, then Advanced settings, each in the list's sections and order
    func sections(basic: Bool) -> [String] {
        settings.filter { $0.basic == basic }.reduce(into: []) { if !$0.contains($1.sectionTitle) { $0.append($1.sectionTitle) } }
    }
    func rows(in section: String, basic: Bool) -> [Setting] { rows(in: section).filter { $0.basic == basic } }
    // A range's label: its percentage, with the size in pixels for the chosen console mode when the list has the base size (the render scale)
    func rangeLabel(_ s: Setting, _ v: Double) -> String {
        let p = "\(Int((v * 100).rounded())) %"
        guard let b = s.base else { return p }
        let size = (values["DM_OPMODE"] ?? "1") == "0" ? b.handheld : b.docked
        guard size.count == 2 else { return p }
        return "\(Int((Double(size[0]) * v).rounded())) × \(Int((Double(size[1]) * v).rounded())) (\(p))"
    }
    var changed: Bool { settings.contains { !fixed.contains($0.env) && !$0.isDefault(values[$0.env] ?? $0.def) } }

    // Reset every launcher choice to the game's defaults on the screen; values fixed by an env file or at launch stay. The saved choices are forgotten when Play applies
    // the defaults (apply() keeps no default), so Quit after Reset keeps them, and a choice a launch override hides is kept
    func reset() {
        for s in settings where !fixed.contains(s.env) { values[s.env] = s.def }
        fputs("launcher: settings reset to the game's defaults\n", stderr)
    }

    // Before the game starts: every setting not set by an env file goes into the environment (DM_LANG replaces the packed language main.m set as a default). Only a choice that
    // differs from the game's default is stored: a setting the player left at its default follows the defaults of a later build (the settings it was tested with)
    func apply() {
        for s in settings {
            let v = values[s.env] ?? s.def
            if fixed.contains(s.env) { fputs("launcher: \(s.env) kept at \(v) (\(fromLaunch.contains(s.env) ? "launch environment" : "env file"))\n", stderr); continue }
            store(s, v)
            setenv(s.env, v, 1); fputs("launcher: \(s.env)=\(v)\(s.isDefault(v) ? "" : " (changed)")\n", stderr)
        }
    }
    private func store(_ s: Setting, _ v: String) {
        if !ignoreSaved { if s.isDefault(v) { defaults.removeObject(forKey: "launcher." + s.env) } else { defaults.set(v, forKey: "launcher." + s.env) } }
    }

    // A choice made while the game runs (the iOS in-game menu, GameMenu.swift): saved as Play saves it, so the settings screen shows it at the next start, and put in the environment.
    // A value an env file or the launch fixed stays
    func choose(_ s: Setting, _ v: String) {
        guard !fixed.contains(s.env), s.accepts(v) else { return }
        values[s.env] = v; store(s, v); setenv(s.env, v, 1)
        fputs("launcher: \(s.env)=\(v) (in-game menu)\n", stderr)
    }

    // DM_LAUNCHER=0: no screen, but the saved choices still apply (only DM_SAVED_CHOICES=0 ignores them); nothing is written
    func applySaved() {
        for s in settings where !fixed.contains(s.env) {
            let v = values[s.env] ?? s.def
            if !s.isDefault(v) { setenv(s.env, v, 1); fputs("launcher: \(s.env)=\(v) (saved choice)\n", stderr) }
        }
    }
}
