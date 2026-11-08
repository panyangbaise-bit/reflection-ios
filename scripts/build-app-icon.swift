import AppKit
import CryptoKit
import Foundation

// App icon pipeline for 复盘了 / Portfolio Review.
//
// Turns the checked-in icon sources into the Icon Composer document that Xcode
// consumes, then validates it with Apple's own renderer.
//
//   cd ios
//   swift scripts/build-app-icon.swift              # regenerate PortfolioAgent/AppIcon.icon
//   swift scripts/build-app-icon.swift --verify     # build + validate + render all six iOS renditions
//   swift scripts/build-app-icon.swift --previews   # build + render previews into docs/brand/assets/icon-renders
//
// Inputs (authored by hand):
//   docs/brand/icon/palette.json        colors per appearance + group metadata
//   docs/brand/icon/layers/*.svg        white alpha-mask artwork, one file per layer
//
// Outputs (generated, never hand-edited):
//   PortfolioAgent/AppIcon.icon/icon.json
//   PortfolioAgent/AppIcon.icon/Assets/*.svg
//   docs/brand/assets/icon-renders/**    (only with --previews; 8-bit sRGB exports of
//                                         the raw 16-bit ictool renders, for repo size)
//
// palette.json schema
// -------------------
// {
//   "designGeneration": 27,                      // 26 or 27; passed to ictool --design-generation
//   "document": {
//     "fillType": "automatic-gradient",          // "automatic-gradient" (default) or "solid"
//     "fill": { "light": "#F2EEE4",              // required: base appearance (also Default)
//               "dark": "#191C21",               // optional: Dark appearance
//               "tinted": "#23324F" }            // optional: Tinted appearances
//   },
//   "groups": [                                  // FRONT to BACK (index 0 is the front-most group)
//     { "name": "Board", "specular": true, "lighting": "individual",
//       "shadow": "none" }                       // shadow: none | neutral | layer-color,
//   ],                                           //   or { "kind": ..., "opacity": 0.5 }
//   "layers": [                                  // order within a group is FRONT to BACK too
//     { "name": "Board", "asset": "board.svg", "group": "Board",
//       "fillType": "automatic-gradient",         // optional, per layer: "solid" (default) or
//                                                 // "automatic-gradient"
//       "fills": { "light": "#FFFFFF", "dark": "#22262E", "tinted": "#16304F" } }
//   ]
// }
//
// Optional group keys beyond the schema above: opacity, hidden, translucency
// (bool or { "enabled": bool, "value": number }), blendMode. Optional layer keys:
// opacity, hidden, glass, blendMode. Unknown palette keys are reported as warnings.
//
// Icon Composer behavior encoded here (verified against Icon Composer 27.0 / ictool 129)
// --------------------------------------------------------------------------------------
// * `groups` and each group's `layers` array are ordered FRONT to BACK. Index 0 is
//   the top-most item in the Icon Composer layer list and paints over later items
//   (verified with a controlled red-over-green overlay test). palette.json uses the
//   same order so no reversal happens anywhere in this script.
// * An asset is only an alpha mask; its own colors are ignored, so layers carry their
//   color as a fill. IMPORTANT: a direct `fill` is final — Icon Composer and ictool
//   silently ignore a sibling `fill-specializations` array (verified with controlled
//   renders; real Icon Composer documents never store both at one level). Appearance-
//   aware fills are therefore encoded ONLY as a specialization array whose first
//   no-appearance entry is the light/default value, followed by the dark/tinted values.
//   Layers with a fixed color get a plain `fill`.
// * SVG documents may not contain <text>: CoreSVG silently drops the text and ictool
//   keeps going, so this script rejects text elements itself.
// * A referenced asset that is missing does not fail ictool (it renders without the
//   layer) but IS caught by actool. Both are checked by --verify.
// * Document-level `fill` takes {"automatic-gradient": color} (subtle system-style
//   vertical gradient) or {"solid": color}; layers always use {"solid": color}.
// * Colors are `extended-srgb:r,g,b,a` with components in 0...1.
// * At most 4 visible groups are allowed; actool reports "Icon validation failed."
//   for more, so the palette loader rejects it early.
// * ictool accepts --design-generation 26|27. On this machine the default is 27 and an
//   explicit 27 render is byte-identical to the unflagged render; --verify asserts the
//   27 render differs from a forced 26 render so a silently ignored flag cannot slip by.
// * ictool writes width × height × scale pixels; at scale 1, 1024 points = 1024 px.
//   Renders are 16-bit PNGs with the iOS icon mask (rounded corners, transparent).
// * ictool exits 0 and prints "{}" on stdout when it considers the document valid; it
//   ignores unknown JSON keys. actool compiles an .icon bundle directly when the input
//   is named <app-icon>.icon (basename must match --app-icon).
//
// The generated bundle is written atomically: the new document is staged in a hidden
// sibling directory and swapped in, so a watching build never sees a half-written icon.
// Builds are idempotent: an up-to-date bundle is left untouched (mtime included).

// MARK: - Constants

let renditionNames = ["Default", "Dark", "TintedLight", "TintedDark", "ClearLight", "ClearDark"]

let renditionNotes: [String: String] = [
    "Default": "light",
    "Dark": "dark",
    "TintedLight": "tinted · light",
    "TintedDark": "tinted · dark",
    "ClearLight": "clear · light",
    "ClearDark": "clear · dark",
]

/// Icon render sizes used by iOS for the home screen / settings / notifications, in points.
let ladderPointSizes = [180, 120, 80, 60, 40, 29]

/// Native pixel density for the ladder renders (`Nx` assets, like an @3x phone).
let ladderRasterScale = 3

/// Rendition size used by --verify and by the per-rendition preview exports.
let renditionPixelSize = 1024

/// Fonts must be registered for previews; this is the repo's mono face.
let monoFontRelativePath = "PortfolioAgent/Resources/IBMPlexMono-Medium.ttf"

// MARK: - Errors

struct IconBuildError: Error, CustomStringConvertible {
    let message: String
    let details: [String]

    init(_ message: String, details: [String] = []) {
        self.message = message
        self.details = details
    }

    var description: String { message }
}

// MARK: - Small utilities

func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func dataText(_ data: Data) -> String {
    String(data: data, encoding: .utf8) ?? ""
}

func trimmedText(_ data: Data) -> String {
    dataText(data).trimmingCharacters(in: .whitespacesAndNewlines)
}

func formattedBytes(_ count: Int) -> String {
    if count >= 1_048_576 { return String(format: "%.1f MB", Double(count) / 1_048_576) }
    if count >= 1024 { return String(format: "%.1f KB", Double(count) / 1024) }
    return "\(count) B"
}

func padded(_ text: String, to width: Int) -> String {
    text + String(repeating: " ", count: max(0, width - text.count))
}

func relativePath(_ url: URL, from root: URL) -> String {
    let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
    if url.path.hasPrefix(prefix) { return String(url.path.dropFirst(prefix.count)) }
    return url.path
}

func fileSize(at url: URL) -> Int {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
}

/// "#RRGGBB" -> extended-sRGB components, or nil when the string is malformed.
func hexComponents(_ hex: String) -> (r: Double, g: Double, b: Double)? {
    guard hex.count == 7, hex.hasPrefix("#"), hex.dropFirst().allSatisfy({ $0.isHexDigit }) else {
        return nil
    }
    let value = UInt32(hex.dropFirst(), radix: 16)!
    return (Double((value >> 16) & 0xFF) / 255.0, Double((value >> 8) & 0xFF) / 255.0, Double(value & 0xFF) / 255.0)
}

/// "#RRGGBB" -> "extended-srgb:r,g,b,1.00000", the color encoding icon.json expects.
func extendedSRGB(_ hex: String) -> String? {
    guard let c = hexComponents(hex) else { return nil }
    return String(format: "extended-srgb:%.5f,%.5f,%.5f,1.00000", c.r, c.g, c.b)
}

/// Parses "extended-srgb:r,g,b,a" back into components (used by --verify schema checks).
func parseExtendedSRGB(_ value: String) -> (r: Double, g: Double, b: Double, a: Double)? {
    let prefix = "extended-srgb:"
    guard value.hasPrefix(prefix) else { return nil }
    let parts = value.dropFirst(prefix.count).split(separator: ",", omittingEmptySubsequences: false)
    guard parts.count == 4 else { return nil }
    var components: [Double] = []
    for part in parts {
        guard let number = Double(part.trimmingCharacters(in: .whitespaces)) else { return nil }
        components.append(number)
    }
    return (components[0], components[1], components[2], components[3])
}

func commandOutput(_ url: URL, scratch: URL, logName: String) throws -> String {
    try trimmedText(runProcess(url, [], scratch: scratch, logName: logName).stdout)
}

// MARK: - CLI

struct Options {
    var verify = false
    var previews = false
    var showHelp = false
    var sourceDir: URL?
    var bundleURL: URL?
    var previewsDir: URL?

    static let usage = """
    usage: swift scripts/build-app-icon.swift [--verify] [--previews]

      (no flags)   regenerate PortfolioAgent/AppIcon.icon from docs/brand/icon/
      --verify     build, validate the palette/bundle, render all six 1024 px renditions
                   with Apple's Icon Composer ictool, and compile the bundle with actool
      --previews   build, render the six 1024 px renditions plus a 180/120/80/60/40/29 pt
                   size ladder, and compose PNG contact sheets into
                   docs/brand/assets/icon-renders/

    optional (development only):
      --source-dir <dir>    read palette.json + layers/ from <dir> instead of docs/brand/icon
      --bundle <path>       write the .icon bundle to <path> instead of PortfolioAgent/AppIcon.icon
      --previews-dir <dir>  write previews to <dir> instead of docs/brand/assets/icon-renders
      --help                print this message

    Run from the ios/ directory. The bundle is generated; never edit it by hand.
    """
}

func parseOptions(_ arguments: [String]) throws -> Options {
    var options = Options()
    var index = 1
    while index < arguments.count {
        switch arguments[index] {
        case "--verify":
            options.verify = true
        case "--previews":
            options.previews = true
        case "--help", "-h":
            options.showHelp = true
        case "--source-dir":
            index += 1
            guard index < arguments.count else { throw IconBuildError("--source-dir needs a path") }
            options.sourceDir = URL(fileURLWithPath: arguments[index])
        case "--bundle":
            index += 1
            guard index < arguments.count else { throw IconBuildError("--bundle needs a path") }
            options.bundleURL = URL(fileURLWithPath: arguments[index])
        case "--previews-dir":
            index += 1
            guard index < arguments.count else { throw IconBuildError("--previews-dir needs a path") }
            options.previewsDir = URL(fileURLWithPath: arguments[index])
        default:
            throw IconBuildError("unknown argument: \(arguments[index])", details: [Options.usage])
        }
        index += 1
    }
    return options
}

// MARK: - Palette model

struct FillColors {
    let light: String
    let dark: String?
    let tinted: String?
}

struct Translucency {
    let enabled: Bool
    let value: Double
}

struct GroupSpec {
    let name: String
    let specular: Bool
    let lighting: String
    let shadowKind: String
    let shadowOpacity: Double
    let opacity: Double?
    let hidden: Bool?
    let translucency: Translucency?
    let blendMode: String?
}

struct LayerSpec {
    let name: String
    let asset: String
    let group: String
    let fillType: String
    let fills: FillColors
    let opacity: Double?
    let hidden: Bool?
    let glass: Bool?
    let blendMode: String?
}

struct Palette {
    let designGeneration: Int
    let fillType: String
    let documentFill: FillColors
    let groups: [GroupSpec]
    let layers: [LayerSpec]

    func layers(inGroup name: String) -> [LayerSpec] {
        layers.filter { $0.group == name }
    }
}

// MARK: - Palette loading & validation

final class PaletteIssues {
    var errors: [String] = []
    var warnings: [String] = []

    func fail(_ message: String) { errors.append(message) }
    func warn(_ message: String) { warnings.append(message) }
}

func loadPalette(at url: URL) throws -> (palette: Palette, warnings: [String]) {
    let fm = FileManager.default
    guard fm.fileExists(atPath: url.path) else {
        throw IconBuildError("missing palette.json", details: [
            "expected: \(url.path)",
            "palette.json and layers/*.svg are authored under docs/brand/icon/.",
            "Run from the ios/ directory: cd ios && swift scripts/build-app-icon.swift",
        ])
    }
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        throw IconBuildError("cannot read palette.json", details: [error.localizedDescription])
    }
    let object: Any
    do {
        object = try JSONSerialization.jsonObject(with: data)
    } catch {
        throw IconBuildError("palette.json is not valid JSON", details: [
            url.path,
            error.localizedDescription,
        ])
    }
    guard let top = object as? [String: Any] else {
        throw IconBuildError("palette.json: the top level must be a JSON object")
    }

    let issues = PaletteIssues()
    warnUnknownKeys(top, allowed: ["designGeneration", "document", "groups", "layers"], path: "palette.json", issues)

    // designGeneration
    var designGeneration = 27
    if let raw = top["designGeneration"] {
        if let number = raw as? NSNumber {
            designGeneration = number.intValue
        } else {
            issues.fail("palette.json: designGeneration must be an integer (26 or 27)")
        }
    } else {
        issues.warn("palette.json: missing designGeneration; assuming 27")
    }
    if designGeneration != 26 && designGeneration != 27 {
        issues.fail("palette.json: designGeneration must be 26 or 27 (got \(designGeneration))")
    }

    // document
    let documentFill: FillColors
    var fillType = "automatic-gradient"
    if let document = top["document"] as? [String: Any] {
        warnUnknownKeys(document, allowed: ["fill", "fillType"], path: "document", issues)
        if let rawFillType = document["fillType"] {
            if let value = rawFillType as? String, value == "automatic-gradient" || value == "solid" {
                fillType = value
            } else {
                issues.fail("document.fillType must be \"automatic-gradient\" or \"solid\"")
            }
        }
        if let fillObject = document["fill"] as? [String: Any] {
            documentFill = decodeFillColors(fillObject, path: "document.fill", issues)
        } else {
            issues.fail("document.fill must be an object with at least a \"light\" hex color")
            documentFill = FillColors(light: "#FF00FF", dark: nil, tinted: nil)
        }
    } else {
        issues.fail("palette.json: missing document object (document.fill.light is required)")
        documentFill = FillColors(light: "#FF00FF", dark: nil, tinted: nil)
    }

    // groups (front to back)
    var groups: [GroupSpec] = []
    if let rawGroups = top["groups"] as? [Any] {
        for (index, rawGroup) in rawGroups.enumerated() {
            guard let group = rawGroup as? [String: Any] else {
                issues.fail("groups[\(index)]: expected an object")
                continue
            }
            let path = "groups[\(index)]"
            warnUnknownKeys(group, allowed: ["name", "specular", "lighting", "shadow", "opacity", "hidden", "translucency", "blendMode"], path: path, issues)
            guard let name = requireString(group["name"], "\(path).name", issues) else { continue }
            if groups.contains(where: { $0.name == name }) {
                issues.fail("groups[\(index)].name: duplicate group name \"\(name)\"")
            }
            let specular = optionalBool(group["specular"], "\(path).specular", issues) ?? true
            var lighting = "combined"
            if let raw = group["lighting"] {
                if let value = raw as? String, value == "combined" || value == "individual" {
                    lighting = value
                } else {
                    issues.fail("\(path).lighting must be \"combined\" or \"individual\"")
                }
            }
            let shadow = decodeShadow(group["shadow"], path: "\(path).shadow", issues)
            let opacity = optionalUnitDouble(group["opacity"], "\(path).opacity", issues)
            let hidden = optionalBool(group["hidden"], "\(path).hidden", issues)
            let translucency = decodeTranslucency(group["translucency"], path: "\(path).translucency", issues)
            var blendMode: String?
            if let raw = group["blendMode"] {
                if let value = raw as? String { blendMode = value } else {
                    issues.fail("\(path).blendMode must be a string")
                }
            }
            groups.append(GroupSpec(
                name: name,
                specular: specular,
                lighting: lighting,
                shadowKind: shadow.kind,
                shadowOpacity: shadow.opacity,
                opacity: opacity,
                hidden: hidden,
                translucency: translucency,
                blendMode: blendMode))
        }
    } else {
        issues.fail("palette.json: missing groups array")
    }

    // layers (front to back within their group)
    var layers: [LayerSpec] = []
    if let rawLayers = top["layers"] as? [Any] {
        for (index, rawLayer) in rawLayers.enumerated() {
            guard let layer = rawLayer as? [String: Any] else {
                issues.fail("layers[\(index)]: expected an object")
                continue
            }
            let path = "layers[\(index)]"
            warnUnknownKeys(layer, allowed: ["name", "asset", "group", "fillType", "fills", "opacity", "hidden", "glass", "blendMode"], path: path, issues)
            guard let name = requireString(layer["name"], "\(path).name", issues) else { continue }
            guard let asset = requireString(layer["asset"], "\(path).asset", issues) else { continue }
            if asset.contains("/") || asset.contains("\\") || asset.isEmpty {
                issues.fail("\(path).asset: must be a bare file name inside docs/brand/icon/layers/ (got \"\(asset)\")")
            }
            if !asset.lowercased().hasSuffix(".svg") {
                issues.fail("\(path).asset: layer artwork must be SVG (got \"\(asset)\")")
            }
            guard let groupName = requireString(layer["group"], "\(path).group", issues) else { continue }
            if !groups.contains(where: { $0.name == groupName }) {
                issues.fail("\(path).group: \"\(groupName)\" is not declared in groups[]")
            }
            if layers.contains(where: { $0.name == name && $0.group == groupName }) {
                issues.warn("\(path).name: duplicate layer name \"\(name)\" in group \"\(groupName)\"")
            }
            let fills: FillColors
            if let fillObject = layer["fills"] as? [String: Any] {
                fills = decodeFillColors(fillObject, path: "\(path).fills", issues)
            } else {
                issues.fail("\(path).fills must be an object with at least a \"light\" hex color")
                fills = FillColors(light: "#FF00FF", dark: nil, tinted: nil)
            }
            var layerFillType = "solid"
            if let rawFillType = layer["fillType"] {
                if let value = rawFillType as? String, value == "solid" || value == "automatic-gradient" {
                    layerFillType = value
                } else {
                    issues.fail("\(path).fillType must be \"solid\" or \"automatic-gradient\"")
                }
            }
            let opacity = optionalUnitDouble(layer["opacity"], "\(path).opacity", issues)
            let hidden = optionalBool(layer["hidden"], "\(path).hidden", issues)
            let glass = optionalBool(layer["glass"], "\(path).glass", issues)
            var blendMode: String?
            if let raw = layer["blendMode"] {
                if let value = raw as? String { blendMode = value } else {
                    issues.fail("\(path).blendMode must be a string")
                }
            }
            layers.append(LayerSpec(
                name: name,
                asset: asset,
                group: groupName,
                fillType: layerFillType,
                fills: fills,
                opacity: opacity,
                hidden: hidden,
                glass: glass,
                blendMode: blendMode))
        }
    } else {
        issues.fail("palette.json: missing layers array")
    }

    // Platform limits and cross references.
    let visibleGroups = groups.filter { $0.hidden != true }
    if visibleGroups.count > 4 {
        issues.fail("palette.json: \(visibleGroups.count) visible groups; Icon Composer supports at most 4 (mark extras hidden or merge them)")
    }
    for group in groups where layers.filter({ $0.group == group.name }).isEmpty && group.hidden != true {
        issues.warn("palette.json: group \"\(group.name)\" has no layers; it will be emitted empty")
    }

    guard issues.errors.isEmpty else {
        throw IconBuildError("palette.json rejected (\(issues.errors.count) issue\(issues.errors.count == 1 ? "" : "s"))", details: issues.errors)
    }

    return (
        Palette(
            designGeneration: designGeneration,
            fillType: fillType,
            documentFill: documentFill,
            groups: groups,
            layers: layers),
        issues.warnings)
}

/// Parses a fill object: { "light": "#RRGGBB", "dark": ..., "tinted": ... }.
func decodeFillColors(_ object: [String: Any], path: String, _ issues: PaletteIssues) -> FillColors {
    warnUnknownKeys(object, allowed: ["light", "dark", "tinted"], path: path, issues)
    let light = decodeColor(object["light"], path: "\(path).light", required: true, issues) ?? "#FF00FF"
    let dark = decodeColor(object["dark"], path: "\(path).dark", required: false, issues)
    let tinted = decodeColor(object["tinted"], path: "\(path).tinted", required: false, issues)
    return FillColors(light: light, dark: dark, tinted: tinted)
}

func decodeColor(_ raw: Any?, path: String, required: Bool, _ issues: PaletteIssues) -> String? {
    guard let raw else {
        if required { issues.fail("\(path): required \"#RRGGBB\" color is missing") }
        return nil
    }
    guard let value = raw as? String, let components = hexComponents(value) else {
        issues.fail("\(path): expected a \"#RRGGBB\" hex color (got \(raw))")
        return nil
    }
    _ = components
    return value
}

func decodeShadow(_ raw: Any?, path: String, _ issues: PaletteIssues) -> (kind: String, opacity: Double) {
    guard let raw else { return ("neutral", 0.5) }
    if let value = raw as? String {
        if ["none", "neutral", "layer-color"].contains(value) {
            return (value, 0.5)
        }
        issues.fail("\(path): shadow shorthand must be one of none / neutral / layer-color (got \"\(value)\")")
        return ("neutral", 0.5)
    }
    if let object = raw as? [String: Any] {
        warnUnknownKeys(object, allowed: ["kind", "opacity"], path: path, issues)
        var kind = "neutral"
        if let rawKind = object["kind"] {
            if let value = rawKind as? String, ["none", "neutral", "layer-color"].contains(value) {
                kind = value
            } else {
                issues.fail("\(path).kind must be one of none / neutral / layer-color")
            }
        }
        let opacity = optionalUnitDouble(object["opacity"], "\(path).opacity", issues) ?? 0.5
        return (kind, opacity)
    }
    issues.fail("\(path): expected a string or { kind, opacity } object")
    return ("neutral", 0.5)
}

func decodeTranslucency(_ raw: Any?, path: String, _ issues: PaletteIssues) -> Translucency? {
    guard let raw else { return nil }
    if let enabled = raw as? Bool {
        return Translucency(enabled: enabled, value: 0.3)
    }
    if let object = raw as? [String: Any] {
        warnUnknownKeys(object, allowed: ["enabled", "value"], path: path, issues)
        let enabled = optionalBool(object["enabled"], "\(path).enabled", issues) ?? false
        let value = optionalUnitDouble(object["value"], "\(path).value", issues) ?? 0.3
        return Translucency(enabled: enabled, value: value)
    }
    issues.fail("\(path): expected a bool or { enabled, value } object")
    return nil
}

func warnUnknownKeys(_ object: [String: Any], allowed: Set<String>, path: String, _ issues: PaletteIssues) {
    for key in object.keys.sorted() where !allowed.contains(key) {
        issues.warn("\(path): unknown key \"\(key)\" (ignored)")
    }
}

func requireString(_ raw: Any?, _ path: String, _ issues: PaletteIssues) -> String? {
    guard let raw else {
        issues.fail("\(path): required string is missing")
        return nil
    }
    guard let value = raw as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        issues.fail("\(path): expected a non-empty string")
        return nil
    }
    return value
}

func optionalBool(_ raw: Any?, _ path: String, _ issues: PaletteIssues) -> Bool? {
    guard let raw else { return nil }
    if let value = raw as? Bool { return value }
    issues.fail("\(path): expected true or false")
    return nil
}

func optionalUnitDouble(_ raw: Any?, _ path: String, _ issues: PaletteIssues) -> Double? {
    guard let raw else { return nil }
    if let value = raw as? NSNumber { return value.doubleValue }
    issues.fail("\(path): expected a number")
    return nil
}

// MARK: - Layer assets

/// Loads every referenced SVG, rejects XML that is not an <svg> root and any text
/// element (Icon Composer/CoreSVG silently drops text, so the failure is otherwise invisible).
func loadLayerAssets(palette: Palette, layersDirectory: URL) throws -> (assets: [String: Data], warnings: [String]) {
    let fm = FileManager.default
    var isDirectory: ObjCBool = false
    guard fm.fileExists(atPath: layersDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw IconBuildError("missing layers directory", details: [
            "expected: \(layersDirectory.path)",
            "Create it with the layer SVGs referenced by palette.json.",
        ])
    }

    var assets: [String: Data] = [:]
    var errors: [String] = []
    var warnings: [String] = []

    for layer in palette.layers {
        let fileURL = layersDirectory.appendingPathComponent(layer.asset)
        guard fm.fileExists(atPath: fileURL.path) else {
            errors.append("missing layer asset: \(layer.asset) (referenced by layer \"\(layer.name)\")")
            continue
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            errors.append("cannot read layer asset \(layer.asset): \(error.localizedDescription)")
            continue
        }
        guard !data.isEmpty else {
            errors.append("empty layer asset: \(layer.asset)")
            continue
        }
        do {
            try validateSVG(data, name: layer.asset)
        } catch let error as IconBuildError {
            errors.append(contentsOf: error.details.isEmpty ? [error.message] : error.details)
        } catch {
            errors.append("layer asset \(layer.asset): \(error)")
        }
        if assets[layer.asset] == nil { assets[layer.asset] = data }
    }

    if let listing = try? fm.contentsOfDirectory(atPath: layersDirectory.path) {
        let referenced = Set(palette.layers.map(\.asset))
        for name in listing.sorted() where !referenced.contains(name) {
            if name.hasPrefix(".") { continue }
            warnings.append("layers/\(name) is not referenced by palette.json (ignored)")
        }
    }

    guard errors.isEmpty else {
        throw IconBuildError("layer assets rejected (\(errors.count) issue\(errors.count == 1 ? "" : "s"))", details: errors)
    }
    return (assets, warnings)
}

func validateSVG(_ data: Data, name: String) throws {
    let document: XMLDocument
    do {
        document = try XMLDocument(data: data, options: [])
    } catch {
        throw IconBuildError("layer asset \(name): not well-formed XML", details: [
            "layer asset \(name): \(error.localizedDescription)",
        ])
    }
    guard let root = document.rootElement() else {
        throw IconBuildError("layer asset \(name): empty SVG document")
    }
    guard root.localName?.lowercased() == "svg" else {
        throw IconBuildError("layer asset \(name): root element must be <svg> (found <\(root.localName ?? root.name ?? "?")>)")
    }

    var textElements: [String] = []
    func walk(_ element: XMLElement) {
        if let localName = element.localName?.lowercased(),
           ["text", "tspan", "textpath"].contains(localName) {
            textElements.append(localName)
        }
        for child in element.children ?? [] {
            if let childElement = child as? XMLElement { walk(childElement) }
        }
    }
    walk(root)

    if !textElements.isEmpty {
        let unique = Array(Set(textElements)).sorted()
        throw IconBuildError("layer asset \(name): contains text elements", details: [
            "layer asset \(name): found <\(unique.joined(separator: ">, <"))>",
            "Icon Composer treats assets as alpha masks and CoreSVG silently drops text; convert lettering to paths.",
        ])
    }
}

// MARK: - icon.json generation

struct Artifacts {
    let manifest: Data
    let assets: [String: Data]

    var manifestSHA: String { sha256Hex(manifest) }
    var assetByteCount: Int { assets.values.reduce(0) { $0 + $1.count } }

    /// Stable hash of icon.json + every asset, used to prove byte-identical builds.
    var treeHash: String {
        var payload = Data()
        payload.append(Data("icon.json".utf8))
        payload.append(0)
        payload.append(manifest)
        for name in assets.keys.sorted() {
            payload.append(Data(name.utf8))
            payload.append(0)
            payload.append(assets[name]!)
        }
        return sha256Hex(payload)
    }
}

func fillRepresentation(hex: String, fillType: String) throws -> [String: Any] {
    guard let color = extendedSRGB(hex) else {
        throw IconBuildError("cannot encode color \"\(hex)\" as extended-srgb")
    }
    return [fillType: color]
}

func fillSpecializations(_ fills: FillColors, fillType: String) throws -> [[String: Any]] {
    var specializations: [[String: Any]] = []
    if let dark = fills.dark {
        specializations.append(["appearance": "dark", "value": try fillRepresentation(hex: dark, fillType: fillType)])
    }
    if let tinted = fills.tinted {
        specializations.append(["appearance": "tinted", "value": try fillRepresentation(hex: tinted, fillType: fillType)])
    }
    return specializations
}

/// Encodes the fill properties for a layer or the document.
///
/// Icon Composer's model is either a direct value or a specialization array — never
/// both. A direct `fill` wins and its `fill-specializations` are silently ignored by
/// ictool, so appearance-aware colors are emitted only as specializations, with the
/// light/default color as the no-appearance entry (the value "all appearances inherit
/// from"). Fixed-color layers get a plain `fill`.
func fillProperties(_ fills: FillColors, fillType: String) throws -> [String: Any] {
    let appearanceSpecializations = try fillSpecializations(fills, fillType: fillType)
    if appearanceSpecializations.isEmpty {
        return ["fill": try fillRepresentation(hex: fills.light, fillType: fillType)]
    }
    let defaultValue: [String: Any] = ["value": try fillRepresentation(hex: fills.light, fillType: fillType)]
    return ["fill-specializations": [defaultValue] + appearanceSpecializations]
}

func makeManifest(palette: Palette) throws -> Data {
    var groupObjects: [[String: Any]] = []
    for group in palette.groups {
        var layerObjects: [[String: Any]] = []
        for layer in palette.layers(inGroup: group.name) {
            var object: [String: Any] = [
                "name": layer.name,
                "image-name": layer.asset,
            ]
            for (key, value) in try fillProperties(layer.fills, fillType: layer.fillType) {
                object[key] = value
            }
            if let opacity = layer.opacity { object["opacity"] = opacity }
            if let hidden = layer.hidden { object["hidden"] = hidden }
            if let glass = layer.glass { object["glass"] = glass }
            if let blendMode = layer.blendMode { object["blend-mode"] = blendMode }
            layerObjects.append(object)
        }

        var groupObject: [String: Any] = [
            "name": group.name,
            "layers": layerObjects,
            "specular": group.specular,
            "lighting": group.lighting,
            "shadow": ["kind": group.shadowKind, "opacity": group.shadowOpacity],
        ]
        if let opacity = group.opacity { groupObject["opacity"] = opacity }
        if let hidden = group.hidden { groupObject["hidden"] = hidden }
        if let translucency = group.translucency {
            groupObject["translucency"] = ["enabled": translucency.enabled, "value": translucency.value]
        }
        if let blendMode = group.blendMode { groupObject["blend-mode"] = blendMode }
        groupObjects.append(groupObject)
    }

    var manifest: [String: Any] = try fillProperties(palette.documentFill, fillType: palette.fillType)
    manifest["groups"] = groupObjects
    manifest["supported-platforms"] = ["squares": ["iOS"]]

    do {
        return try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    } catch {
        throw IconBuildError("cannot serialize icon.json", details: [error.localizedDescription])
    }
}

func makeArtifacts(palette: Palette, assets: [String: Data]) throws -> Artifacts {
    Artifacts(manifest: try makeManifest(palette: palette), assets: assets)
}

// MARK: - Bundle IO

func bundleMatches(_ artifacts: Artifacts, at bundle: URL) -> Bool {
    let fm = FileManager.default
    var isDirectory: ObjCBool = false
    guard fm.fileExists(atPath: bundle.path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
    guard let rootEntries = try? fm.contentsOfDirectory(atPath: bundle.path),
          Set(rootEntries) == ["icon.json", "Assets"] else { return false }
    guard let manifest = try? Data(contentsOf: bundle.appendingPathComponent("icon.json")),
          manifest == artifacts.manifest else { return false }
    let assetsDirectory = bundle.appendingPathComponent("Assets")
    guard let assetEntries = try? fm.contentsOfDirectory(atPath: assetsDirectory.path),
          Set(assetEntries) == Set(artifacts.assets.keys) else { return false }
    for (name, expected) in artifacts.assets {
        guard let actual = try? Data(contentsOf: assetsDirectory.appendingPathComponent(name)),
              actual == expected else { return false }
    }
    return true
}

enum WriteResult {
    case created
    case updated
    case unchanged

    var description: String {
        switch self {
        case .created: return "created"
        case .updated: return "updated"
        case .unchanged: return "unchanged (byte-identical, left untouched)"
        }
    }
}

/// Writes the bundle atomically. The new document is staged in a hidden sibling
/// directory and swapped in so watchers never observe a partially written icon.
func writeBundle(_ artifacts: Artifacts, to bundle: URL) throws -> WriteResult {
    let fm = FileManager.default
    if bundleMatches(artifacts, at: bundle) { return .unchanged }

    let existed = fm.fileExists(atPath: bundle.path)
    let parent = bundle.deletingLastPathComponent()
    try fm.createDirectory(at: parent, withIntermediateDirectories: true)

    let staging = parent.appendingPathComponent(".\(bundle.lastPathComponent).building-\(ProcessInfo.processInfo.processIdentifier)")
    try? fm.removeItem(at: staging)
    do {
        try fm.createDirectory(at: staging.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        try artifacts.manifest.write(to: staging.appendingPathComponent("icon.json"), options: .atomic)
        for name in artifacts.assets.keys.sorted() {
            try artifacts.assets[name]!.write(to: staging.appendingPathComponent("Assets").appendingPathComponent(name), options: .atomic)
        }
    } catch {
        try? fm.removeItem(at: staging)
        throw IconBuildError("cannot stage the icon bundle", details: [error.localizedDescription])
    }

    do {
        if existed {
            do {
                _ = try fm.replaceItemAt(bundle, withItemAt: staging, backupItemName: nil, options: [])
            } catch {
                // Fallback for filesystems where directory replacement is unavailable.
                try? fm.removeItem(at: bundle)
                try fm.moveItem(at: staging, to: bundle)
            }
        } else {
            try fm.moveItem(at: staging, to: bundle)
        }
    } catch {
        try? fm.removeItem(at: staging)
        throw IconBuildError("cannot install the icon bundle at \(bundle.path)", details: [error.localizedDescription])
    }
    return existed ? .updated : .created
}

// MARK: - Process execution

struct CommandResult {
    let status: Int32
    let stdout: Data
    let stderr: Data

    var stdoutText: String { trimmedText(stdout) }
    var stderrText: String { trimmedText(stderr) }
}

/// Runs a tool with stdout/stderr redirected to scratch files. File redirection
/// keeps the pipes from deadlocking on chatty tools such as actool.
func runProcess(_ executable: URL, _ arguments: [String], scratch: URL, logName: String) throws -> CommandResult {
    let fm = FileManager.default
    let safeName = logName.replacingOccurrences(of: "/", with: "-")
    let stdoutURL = scratch.appendingPathComponent("\(safeName).stdout")
    let stderrURL = scratch.appendingPathComponent("\(safeName).stderr")
    try? fm.removeItem(at: stdoutURL)
    try? fm.removeItem(at: stderrURL)
    fm.createFile(atPath: stdoutURL.path, contents: nil)
    fm.createFile(atPath: stderrURL.path, contents: nil)
    guard let stdoutHandle = FileHandle(forWritingAtPath: stdoutURL.path),
          let stderrHandle = FileHandle(forWritingAtPath: stderrURL.path) else {
        throw IconBuildError("cannot open scratch files for \(executable.lastPathComponent)")
    }
    defer {
        try? stdoutHandle.close()
        try? stderrHandle.close()
    }

    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = stdoutHandle
    process.standardError = stderrHandle
    process.standardInput = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        throw IconBuildError("cannot launch \(executable.lastPathComponent)", details: [error.localizedDescription])
    }
    process.waitUntilExit()

    let stdout = (try? Data(contentsOf: stdoutURL)) ?? Data()
    let stderr = (try? Data(contentsOf: stderrURL)) ?? Data()
    try? fm.removeItem(at: stdoutURL)
    try? fm.removeItem(at: stderrURL)
    return CommandResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
}

// MARK: - Tool discovery

struct Renderer {
    let url: URL
    let shortVersion: String
    let bundleVersion: String

    var versionDescription: String { "Icon Composer ictool \(shortVersion) (bundle \(bundleVersion))" }
}

func locateRenderer(scratch: URL) throws -> Renderer {
    var candidates: [URL] = []
    let environment = ProcessInfo.processInfo.environment
    if let override = environment["ICTOOL"], !override.isEmpty {
        candidates.append(URL(fileURLWithPath: override))
    }
    if let developerDir = try? commandOutput(URL(fileURLWithPath: "/usr/bin/xcode-select"), scratch: scratch, logName: "xcode-select").nonEmpty {
        if developerDir.hasSuffix("/Contents/Developer") {
            let contents = URL(fileURLWithPath: developerDir).deletingLastPathComponent()
            candidates.append(contents.appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool"))
        }
    }
    candidates.append(URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"))
    candidates.append(URL(fileURLWithPath: "/Applications/Xcode-beta.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"))

    let fm = FileManager.default
    for candidate in candidates {
        guard fm.isExecutableFile(atPath: candidate.path) else { continue }
        guard let result = try? runProcess(candidate, ["--version"], scratch: scratch, logName: "ictool-version"),
              result.status == 0,
              let object = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any] else { continue }
        let shortVersion = (object["short-bundle-version"] as? String) ?? "?"
        let bundleVersion = (object["bundle-version"] as? String) ?? "?"
        return Renderer(url: candidate, shortVersion: shortVersion, bundleVersion: bundleVersion)
    }

    throw IconBuildError("Icon Composer ictool not found", details: [
        "Looked in:",
        "  $ICTOOL",
    ] + candidates.map { "  \($0.path)" })
}

func locateActool(scratch: URL) -> URL? {
    if let result = try? runProcess(URL(fileURLWithPath: "/usr/bin/xcrun"), ["--find", "actool"], scratch: scratch, logName: "xcrun-actool"),
       result.status == 0 {
        let path = result.stdoutText
        if !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
    }
    for candidate in [
        "/Applications/Xcode.app/Contents/Developer/usr/bin/actool",
        "/Applications/Xcode-beta.app/Contents/Developer/usr/bin/actool",
    ] where FileManager.default.isExecutableFile(atPath: candidate) {
        return URL(fileURLWithPath: candidate)
    }
    return nil
}

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Rendering & PNG analysis

struct RenderAnalysis {
    let url: URL
    let width: Int
    let height: Int
    let byteCount: Int
    let signature: String
    let opaqueFraction: Double
    let meanColor: String
}

/// Decodes a rendered PNG and reduces it to a stable pixel signature + simple stats.
/// The signature is what --verify compares across renditions, so two renders that
/// differ only in PNG metadata still count as identical pixels.
func analyzeRender(at url: URL) throws -> RenderAnalysis {
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        throw IconBuildError("cannot read render \(url.lastPathComponent)", details: [error.localizedDescription])
    }
    guard !data.isEmpty else {
        throw IconBuildError("render \(url.lastPathComponent) is empty")
    }
    guard let representation = NSBitmapImageRep(data: data), let image = representation.cgImage else {
        throw IconBuildError("render \(url.lastPathComponent) is not a decodable PNG")
    }
    let width = representation.pixelsWide
    let height = representation.pixelsHigh
    guard width > 0, height > 0 else {
        throw IconBuildError("render \(url.lastPathComponent) has no pixels")
    }

    let bytesPerRow = width * 4
    guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw IconBuildError("cannot analyze render \(url.lastPathComponent)")
    }
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let raw = context.data else {
        throw IconBuildError("cannot analyze render \(url.lastPathComponent)")
    }

    let pixels = raw.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
    var opaqueCount = 0
    var red = 0.0, green = 0.0, blue = 0.0
    for offset in stride(from: 0, to: bytesPerRow * height, by: 4) {
        let alpha = pixels[offset + 3]
        if alpha >= 250 {
            opaqueCount += 1
            red += Double(pixels[offset])
            green += Double(pixels[offset + 1])
            blue += Double(pixels[offset + 2])
        }
    }
    let total = width * height
    let signature = sha256Hex(Data(bytes: pixels, count: bytesPerRow * height))
    let mean: String
    if opaqueCount > 0 {
        mean = String(
            format: "#%02X%02X%02X",
            Int((red / Double(opaqueCount)).rounded()),
            Int((green / Double(opaqueCount)).rounded()),
            Int((blue / Double(opaqueCount)).rounded()))
    } else {
        mean = "transparent"
    }
    return RenderAnalysis(
        url: url,
        width: width,
        height: height,
        byteCount: data.count,
        signature: signature,
        opaqueFraction: Double(opaqueCount) / Double(total),
        meanColor: mean)
}

func renderIcon(
    renderer: Renderer,
    bundle: URL,
    rendition: String,
    pixelSize: Int,
    generation: Int?,
    scratch: URL,
    logName: String) throws -> RenderAnalysis {
    let output = scratch.appendingPathComponent("render-\(logName).png")
    try? FileManager.default.removeItem(at: output)

    var arguments = [
        bundle.path,
        "--export-image",
        "--output-file", output.path,
        "--platform", "iOS",
        "--rendition", rendition,
        "--width", "\(pixelSize)",
        "--height", "\(pixelSize)",
        "--scale", "1",
    ]
    if let generation { arguments.append(contentsOf: ["--design-generation", "\(generation)"]) }

    let result = try runProcess(renderer.url, arguments, scratch: scratch, logName: "render-\(logName)")
    if result.status != 0 {
        throw IconBuildError("ictool exited \(result.status) while rendering \(rendition)", details: [
            result.stderrText,
            result.stdoutText,
        ].filter { !$0.isEmpty })
    }
    if result.stderrText.contains("CoreSVG has logged an error") {
        throw IconBuildError("\(rendition): CoreSVG rejected an SVG asset (text or unsupported SVG feature)")
    }
    guard FileManager.default.fileExists(atPath: output.path) else {
        throw IconBuildError("\(rendition): ictool reported success but wrote no image")
    }
    guard fileSize(at: output) > 0 else {
        throw IconBuildError("\(rendition): ictool wrote an empty image")
    }

    let analysis = try analyzeRender(at: output)
    guard analysis.width == pixelSize, analysis.height == pixelSize else {
        throw IconBuildError("\(rendition): expected \(pixelSize)×\(pixelSize), got \(analysis.width)×\(analysis.height)")
    }
    guard analysis.opaqueFraction >= 0.05 else {
        throw IconBuildError("\(rendition): render appears empty (\(Int(analysis.opaqueFraction * 100))% opaque pixels)")
    }
    return analysis
}

// MARK: - Check log

final class CheckLog {
    private(set) var passed = 0
    private(set) var warned = 0
    private(set) var failed = 0

    func section(_ title: String) {
        print("")
        print(title)
    }

    func pass(_ name: String, _ detail: String = "") {
        passed += 1
        line("PASS", name, detail)
    }

    func warn(_ name: String, _ detail: String = "") {
        warned += 1
        line("WARN", name, detail)
    }

    func fail(_ name: String, _ detail: String = "") {
        failed += 1
        line("FAIL", name, detail)
    }

    func detail(_ text: String) {
        for line in text.split(separator: "\n") {
            print("        \(line)")
        }
    }

    func result() -> Bool {
        print("")
        if failed == 0 {
            print("  OK    \(passed) passed · \(warned) warning\(warned == 1 ? "" : "s") · 0 failed")
        } else {
            print("  FAIL  \(failed) failed · \(passed) passed · \(warned) warning\(warned == 1 ? "" : "s")")
        }
        return failed == 0
    }

    private func line(_ status: String, _ name: String, _ detail: String) {
        print("  \(status)  \(padded(name, to: 30))  \(detail)")
    }
}

// MARK: - icon.json schema validation (independent of the generator)

struct ManifestStats {
    let groupCount: Int
    let layerCount: Int
}

/// Re-reads the generated icon.json and rejects anything we do not expect to emit.
/// This is the "no unsupported keys" gate: ictool and actool both ignore unknown keys,
/// so only our own schema check can catch a generator regression.
func validateManifestSchema(_ data: Data, expectedAssets: Set<String>) throws -> ManifestStats {
    var problems: [String] = []
    let allowedTop: Set<String> = ["fill", "fill-specializations", "groups", "supported-platforms"]
    let allowedGroup: Set<String> = ["name", "layers", "specular", "lighting", "shadow", "opacity", "hidden", "translucency", "blend-mode"]
    let allowedLayer: Set<String> = ["name", "image-name", "fill", "fill-specializations", "opacity", "hidden", "glass", "blend-mode"]
    let allowedFill: Set<String> = ["solid", "automatic-gradient"]
    let allowedSpecialization: Set<String> = ["appearance", "value"]

    guard let top = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        throw IconBuildError("icon.json does not parse as a JSON object")
    }

    func checkUnknownKeys(_ object: [String: Any], allowed: Set<String>, path: String) {
        for key in object.keys.sorted() where !allowed.contains(key) {
            problems.append("\(path): unsupported key \"\(key)\"")
        }
    }

    func checkFill(_ raw: Any?, path: String) {
        guard let fill = raw as? [String: Any] else {
            problems.append("\(path): expected a fill object")
            return
        }
        let keys = Set(fill.keys)
        guard !keys.isEmpty, keys.isSubset(of: allowedFill) else {
            problems.append("\(path): expected exactly one of solid/automatic-gradient (found \(keys.sorted()))")
            return
        }
        if keys.count != 1 {
            problems.append("\(path): expected exactly one of solid/automatic-gradient (found \(keys.sorted()))")
            return
        }
        if let value = fill.values.first as? String {
            if parseExtendedSRGB(value) == nil {
                problems.append("\(path): invalid extended-srgb color string")
            }
        } else {
            problems.append("\(path): expected an extended-srgb color string")
        }
    }

    func checkSpecializations(_ raw: Any?, path: String) {
        guard let array = raw as? [Any] else {
            problems.append("\(path): expected an array")
            return
        }
        var seen: Set<String> = []
        var defaultEntries = 0
        for (index, item) in array.enumerated() {
            let itemPath = "\(path)[\(index)]"
            guard let object = item as? [String: Any] else {
                problems.append("\(itemPath): expected an object")
                continue
            }
            checkUnknownKeys(object, allowed: allowedSpecialization, path: itemPath)
            if let appearance = object["appearance"] as? String {
                guard ["dark", "tinted"].contains(appearance) else {
                    problems.append("\(itemPath).appearance: expected \"dark\" or \"tinted\"")
                    continue
                }
                if seen.contains(appearance) { problems.append("\(itemPath): duplicate appearance \"\(appearance)\"") }
                seen.insert(appearance)
            } else {
                defaultEntries += 1
                if defaultEntries > 1 { problems.append("\(itemPath): more than one default (no-appearance) entry") }
            }
            checkFill(object["value"], path: "\(itemPath).value")
        }
    }

    checkUnknownKeys(top, allowed: allowedTop, path: "icon.json")

    /// A value is encoded either as a direct fill or as a specialization array; storing
    /// both makes ictool ignore the specializations, so reject it here.
    func checkFillContainer(_ object: [String: Any], path: String) {
        let hasDirect = object["fill"] != nil
        let hasSpecializations = object["fill-specializations"] != nil
        if hasDirect && hasSpecializations {
            problems.append("\(path): has both fill and fill-specializations — Icon Composer ignores the specializations when a direct fill is present")
        }
        if !hasDirect && !hasSpecializations {
            problems.append("\(path): missing fill or fill-specializations")
        }
        if hasDirect { checkFill(object["fill"], path: "\(path).fill") }
        if let specializations = object["fill-specializations"] {
            checkSpecializations(specializations, path: "\(path).fill-specializations")
        }
    }

    checkFillContainer(top, path: "document")

    if let platforms = top["supported-platforms"] as? [String: Any] {
        let squares = platforms["squares"] as? [String]
        if squares != ["iOS"] {
            problems.append("supported-platforms.squares: expected [\"iOS\"]")
        }
        checkUnknownKeys(platforms, allowed: ["squares"], path: "supported-platforms")
    } else {
        problems.append("supported-platforms: expected { squares: [\"iOS\"] }")
    }

    var groupCount = 0
    var layerCount = 0
    var referencedAssets: Set<String> = []
    if let groups = top["groups"] as? [Any] {
        groupCount = groups.count
        for (groupIndex, rawGroup) in groups.enumerated() {
            guard let group = rawGroup as? [String: Any] else {
                problems.append("groups[\(groupIndex)]: expected an object")
                continue
            }
            let groupPath = "groups[\(groupIndex)]"
            checkUnknownKeys(group, allowed: allowedGroup, path: groupPath)
            if let shadow = group["shadow"] as? [String: Any] {
                checkUnknownKeys(shadow, allowed: ["kind", "opacity"], path: "\(groupPath).shadow")
                if let kind = shadow["kind"] as? String, !["none", "neutral", "layer-color"].contains(kind) {
                    problems.append("\(groupPath).shadow.kind: invalid value \"\(kind)\"")
                }
                if shadow["opacity"] as? NSNumber == nil {
                    problems.append("\(groupPath).shadow.opacity: expected a number")
                }
            } else {
                problems.append("\(groupPath).shadow: expected { kind, opacity }")
            }
            if let lighting = group["lighting"] as? String, !["combined", "individual"].contains(lighting) {
                problems.append("\(groupPath).lighting: invalid value \"\(lighting)\"")
            }
            guard let layers = group["layers"] as? [Any] else {
                problems.append("\(groupPath).layers: expected an array")
                continue
            }
            layerCount += layers.count
            for (layerIndex, rawLayer) in layers.enumerated() {
                guard let layer = rawLayer as? [String: Any] else {
                    problems.append("\(groupPath).layers[\(layerIndex)]: expected an object")
                    continue
                }
                let layerPath = "\(groupPath).layers[\(layerIndex)]"
                checkUnknownKeys(layer, allowed: allowedLayer, path: layerPath)
                guard let name = layer["name"] as? String, !name.isEmpty else {
                    problems.append("\(layerPath).name: expected a non-empty string")
                    continue
                }
                guard let imageName = layer["image-name"] as? String, !imageName.isEmpty else {
                    problems.append("\(layerPath).image-name: expected a non-empty string")
                    continue
                }
                referencedAssets.insert(imageName)
                checkFillContainer(layer, path: "\(layerPath) (\"\(name)\")")
            }
        }
    } else {
        problems.append("groups: expected an array")
    }

    let missing = referencedAssets.subtracting(expectedAssets)
    if !missing.isEmpty {
        problems.append("manifest references assets that were not staged: \(missing.sorted().joined(separator: ", "))")
    }

    guard problems.isEmpty else {
        throw IconBuildError("icon.json failed schema validation (\(problems.count) issue\(problems.count == 1 ? "" : "s"))", details: problems)
    }
    return ManifestStats(groupCount: groupCount, layerCount: layerCount)
}

// MARK: - Preview composition (AppKit)

/// A small raster canvas with top-left coordinates, used for contact sheets.
final class Canvas {
    let width: Int
    let height: Int
    private let context: CGContext
    private let logicalWidth: CGFloat
    private let logicalHeight: CGFloat

    init(width: Int, height: Int, background: NSColor? = nil) {
        self.width = width
        self.height = height
        self.logicalWidth = CGFloat(width)
        self.logicalHeight = CGFloat(height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("cannot create a \(width)×\(height) canvas")
        }
        self.context = context
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        if let background {
            fillRect(x: 0, top: 0, width: logicalWidth, height: logicalHeight, color: background)
        }
    }

    func finish() {
        NSGraphicsContext.restoreGraphicsState()
    }

    private func rectFor(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: x, y: logicalHeight - top - height, width: width, height: height)
    }

    func fillRect(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat, color: NSColor) {
        context.setFillColor(color.cgColor)
        context.fill(rectFor(x: x, top: top, width: width, height: height))
    }

    func checkerboard(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat, cell: CGFloat = 16) {
        let light = NSColor(srgbRed: 0.972, green: 0.961, blue: 0.933, alpha: 1)
        let dark = NSColor(srgbRed: 0.898, green: 0.878, blue: 0.835, alpha: 1)
        fillRect(x: x, top: top, width: width, height: height, color: light)
        var row = 0
        var offsetY: CGFloat = 0
        while offsetY < height {
            var column = 0
            var offsetX: CGFloat = 0
            while offsetX < width {
                if (row + column) % 2 == 1 {
                    let cellWidth = min(cell, width - offsetX)
                    let cellHeight = min(cell, height - offsetY)
                    fillRect(x: x + offsetX, top: top + offsetY, width: cellWidth, height: cellHeight, color: dark)
                }
                column += 1
                offsetX += cell
            }
            row += 1
            offsetY += cell
        }
    }

    func drawImage(_ image: CGImage, x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) {
        context.interpolationQuality = .high
        context.draw(image, in: rectFor(x: x, top: top, width: width, height: height))
    }

    func text(_ string: String, font: NSFont, color: NSColor, x: CGFloat, top: CGFloat, tracking: CGFloat = 0) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: tracking,
        ]
        let attributed = NSAttributedString(string: string, attributes: attributes)
        let size = attributed.size()
        attributed.draw(at: NSPoint(x: x, y: logicalHeight - top - size.height))
    }

    func textWidth(_ string: String, font: NSFont, tracking: CGFloat = 0) -> CGFloat {
        NSAttributedString(string: string, attributes: [.font: font, .kern: tracking]).size().width
    }

    func save(to url: URL) throws {
        context.flush()
        guard let image = context.makeImage() else {
            throw IconBuildError("cannot snapshot the preview canvas")
        }
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw IconBuildError("cannot encode PNG for \(url.lastPathComponent)")
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw IconBuildError("cannot write \(url.path)", details: [error.localizedDescription])
        }
    }
}

func loadPreviewImage(at url: URL) throws -> CGImage {
    guard let data = try? Data(contentsOf: url),
          let representation = NSBitmapImageRep(data: data),
          let image = representation.cgImage else {
        throw IconBuildError("cannot decode \(url.lastPathComponent) for the contact sheet")
    }
    return image
}

// Colors and fonts used by the preview sheets (match docs/brand/brand.md).
func previewInk() -> NSColor { NSColor(srgbRed: 0.06, green: 0.07, blue: 0.08, alpha: 1) }
func previewMuted() -> NSColor { NSColor(srgbRed: 0.42, green: 0.42, blue: 0.42, alpha: 1) }
func previewHairline() -> NSColor { NSColor(srgbRed: 0.80, green: 0.78, blue: 0.74, alpha: 1) }
func previewPaper() -> NSColor { NSColor(srgbRed: 0.957, green: 0.945, blue: 0.918, alpha: 1) }

func previewMonoFont(_ size: CGFloat) -> NSFont {
    NSFont(name: "IBMPlexMono-Medium", size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .medium)
}

func previewSansFont(_ size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let name = weight == .semibold ? "PingFangSC-Semibold" : "PingFangSC-Regular"
    return NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
}

func composeRenditionsSheet(entries: [(name: String, note: String, image: CGImage)], generation: Int, to url: URL) throws {
    let margin: CGFloat = 96
    let gapX: CGFloat = 72
    let gapY: CGFloat = 56
    let cell: CGFloat = 512
    let labelHeight: CGFloat = 92
    let titleHeight: CGFloat = 196
    let footerHeight: CGFloat = 96
    let columns = 3
    let rows = 2
    let width = margin * 2 + cell * CGFloat(columns) + gapX * CGFloat(columns - 1)
    let height = titleHeight + CGFloat(rows) * (cell + labelHeight) + gapY * CGFloat(rows - 1) + footerHeight
    let canvas = Canvas(width: Int(width), height: Int(height), background: previewPaper())
    defer { canvas.finish() }

    canvas.text("复盘了 · APP ICON", font: previewSansFont(64, weight: .semibold), color: previewInk(), x: margin, top: 52)
    canvas.text("iOS 27 · SIX APPEARANCE RENDITIONS · 1024 PX", font: previewMonoFont(26), color: previewMuted(), x: margin + 2, top: 138, tracking: 2.0)
    let generationText = "GENERATION \(generation)"
    let generationWidth = canvas.textWidth(generationText, font: previewMonoFont(26), tracking: 2.0)
    canvas.text(generationText, font: previewMonoFont(26), color: previewMuted(), x: width - margin - generationWidth, top: 52, tracking: 2.0)
    canvas.fillRect(x: margin, top: 186, width: width - margin * 2, height: 2, color: previewInk())

    for (index, entry) in entries.enumerated() {
        let row = index / columns
        let column = index % columns
        let x = margin + CGFloat(column) * (cell + gapX)
        let top = titleHeight + CGFloat(row) * (cell + labelHeight + gapY)
        canvas.checkerboard(x: x, top: top, width: cell, height: cell, cell: 16)
        canvas.drawImage(entry.image, x: x, top: top, width: cell, height: cell)
        canvas.text(entry.name, font: previewMonoFont(36), color: previewInk(), x: x, top: top + cell + 16, tracking: 0.4)
        canvas.text(entry.note.uppercased(), font: previewMonoFont(22), color: previewMuted(), x: x + 2, top: top + cell + 58, tracking: 1.6)
    }

    canvas.fillRect(x: margin, top: height - footerHeight + 6, width: width - margin * 2, height: 1, color: previewHairline())
    canvas.text("RENDERED WITH APPLE ICON COMPOSER ICTOOL · SOURCES: DOCS/BRAND/ICON", font: previewMonoFont(22), color: previewMuted(), x: margin, top: height - footerHeight + 34, tracking: 0.9)
    let toolText = "BRAND/SWIFT SCRIPTS/BUILD-APP-ICON.SWIFT"
    let toolWidth = canvas.textWidth(toolText, font: previewMonoFont(22), tracking: 0.9)
    canvas.text(toolText, font: previewMonoFont(22), color: previewMuted(), x: width - margin - toolWidth, top: height - footerHeight + 34, tracking: 0.9)

    try canvas.save(to: url)
}

func composeLadderSheet(entries: [(points: Int, pixels: Int, image: CGImage)], generation: Int, to url: URL) throws {
    let margin: CGFloat = 96
    let gap: CGFloat = 64
    let displayScale: CGFloat = 2
    let titleHeight: CGFloat = 196
    let labelHeight: CGFloat = 104
    let footerHeight: CGFloat = 96
    let sorted = entries.sorted { $0.points < $1.points }
    let tallest = (sorted.map { CGFloat($0.points) * displayScale }.max() ?? 360)
    let width = margin * 2
        + sorted.reduce(CGFloat(0)) { $0 + CGFloat($1.points) * displayScale }
        + gap * CGFloat(max(0, sorted.count - 1))
    let height = titleHeight + tallest + labelHeight + footerHeight
    let canvas = Canvas(width: Int(width), height: Int(height), background: previewPaper())
    defer { canvas.finish() }

    canvas.text("SIZE LADDER · DEFAULT", font: previewSansFont(64, weight: .semibold), color: previewInk(), x: margin, top: 52)
    canvas.text("NATIVE @\(ladderRasterScale)X RENDERS SHOWN AT POINT SIZE · HOME SCREEN / SETTINGS / NOTIFICATIONS", font: previewMonoFont(24), color: previewMuted(), x: margin + 2, top: 138, tracking: 1.6)
    let generationText = "GENERATION \(generation)"
    let generationWidth = canvas.textWidth(generationText, font: previewMonoFont(26), tracking: 2.0)
    canvas.text(generationText, font: previewMonoFont(26), color: previewMuted(), x: width - margin - generationWidth, top: 52, tracking: 2.0)
    canvas.fillRect(x: margin, top: 186, width: width - margin * 2, height: 2, color: previewInk())

    let baseline = titleHeight + tallest
    var x = margin
    for entry in sorted {
        let side = CGFloat(entry.points) * displayScale
        let top = baseline - side
        canvas.checkerboard(x: x, top: top, width: side, height: side, cell: 12)
        canvas.drawImage(entry.image, x: x, top: top, width: side, height: side)
        canvas.text("\(entry.points) PT", font: previewMonoFont(28), color: previewInk(), x: x, top: baseline + 16, tracking: 0.5)
        canvas.text("\(entry.pixels) PX", font: previewMonoFont(20), color: previewMuted(), x: x + 2, top: baseline + 54, tracking: 0.8)
        x += side + gap
    }

    canvas.fillRect(x: margin, top: height - footerHeight + 6, width: width - margin * 2, height: 1, color: previewHairline())
    canvas.text("RENDERED WITH APPLE ICON COMPOSER ICTOOL · CHECKERBOARD = TRANSPARENT", font: previewMonoFont(22), color: previewMuted(), x: margin, top: height - footerHeight + 34, tracking: 0.9)
    try canvas.save(to: url)
}

// MARK: - App

final class App {
    let options: Options
    let root: URL
    let sourceDirectory: URL
    let bundleURL: URL
    let previewsURL: URL
    let scratchURL: URL

    private var palette: Palette?
    private var layerAssets: [String: Data] = [:]
    private var artifacts: Artifacts?
    private var rendererCache: Renderer?

    init(options: Options) throws {
        self.options = options
        self.root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        self.sourceDirectory = options.sourceDir ?? root.appendingPathComponent("docs/brand/icon")
        self.bundleURL = options.bundleURL ?? root.appendingPathComponent("PortfolioAgent/AppIcon.icon")
        self.previewsURL = options.previewsDir ?? root.appendingPathComponent("docs/brand/assets/icon-renders")

        if options.bundleURL == nil {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent("PortfolioAgent").path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw IconBuildError("not run from the ios/ directory", details: [
                    "current directory: \(root.path)",
                    "Run: cd ios && swift scripts/build-app-icon.swift",
                ])
            }
        }
        self.scratchURL = try App.makeScratchDirectory()
    }

    deinit {
        try? FileManager.default.removeItem(at: scratchURL)
    }

    static func makeScratchDirectory() throws -> URL {
        let fm = FileManager.default
        let candidates: [URL] = [
            URL(fileURLWithPath: ProcessInfo.processInfo.environment["BRAND_ICON_SCRATCH"] ?? "/tmp"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build-app-icon-scratch"),
        ]
        var lastError = ""
        for base in candidates {
            let directory = base.appendingPathComponent("reflection-app-icon-\(ProcessInfo.processInfo.processIdentifier)")
            do {
                try? fm.removeItem(at: directory)
                try fm.createDirectory(at: directory, withIntermediateDirectories: true)
                return directory
            } catch {
                lastError = "\(base.path): \(error.localizedDescription)"
            }
        }
        throw IconBuildError("cannot create a scratch directory", details: [lastError])
    }

    func run() throws {
        print("复盘了 app icon · build-app-icon.swift")
        try loadSources()
        try buildBundle()

        if options.verify {
            let renderer = try rendererInstance()
            let success = try runVerify(renderer: renderer)
            guard success else {
                print("")
                print("verify failed — fix the issues above before wiring the bundle into Xcode.")
                throw IconBuildError("verification failed")
            }
        }

        if options.previews {
            let renderer = try rendererInstance()
            try runPreviews(renderer: renderer)
        }

        print("")
        print("done")
    }

    // MARK: Sources

    private func loadSources() throws {
        let loaded = try loadPalette(at: sourceDirectory.appendingPathComponent("palette.json"))
        for warning in loaded.warnings {
            print("  WARN  \(warning)")
        }
        let assets = try loadLayerAssets(palette: loaded.palette, layersDirectory: sourceDirectory.appendingPathComponent("layers"))
        for warning in assets.warnings {
            print("  WARN  \(warning)")
        }
        palette = loaded.palette
        layerAssets = assets.assets
    }

    // MARK: Build

    private func buildBundle() throws {
        guard let palette else { throw IconBuildError("internal error: palette not loaded") }
        let first = try makeArtifacts(palette: palette, assets: layerAssets)
        let second = try makeArtifacts(palette: palette, assets: layerAssets)
        guard first.manifest == second.manifest, first.assets == second.assets else {
            throw IconBuildError("non-deterministic generation: two builds of the same sources differ")
        }
        artifacts = first
        let result = try writeBundle(first, to: bundleURL)

        print("")
        print("build")
        print("  source    \(padded(relativePath(sourceDirectory, from: root) + "/", to: 48)) palette.json + \(layerAssets.count) layer SVG\(layerAssets.count == 1 ? "" : "s")")
        print("  palette   \(padded("generation \(palette.designGeneration) · document \(palette.fillType)", to: 48)) \(palette.groups.count) groups / \(palette.layers.count) layers")
        let order = palette.groups.map { group -> String in
            let count = palette.layers(inGroup: group.name).count
            return count > 0 ? "\(group.name) (\(count))" : group.name
        }.joined(separator: " ▸ ")
        print("  order     \(padded("front → back", to: 48)) \(order)")
        print("  bundle    \(padded(relativePath(bundleURL, from: root), to: 48)) \(result.description)")
        print("            icon.json \(formattedBytes(first.manifest.count)) · sha256 \(first.manifestSHA)")
        print("            \(first.assets.count) asset\(first.assets.count == 1 ? "" : "s") · \(formattedBytes(first.assetByteCount)) · copied byte-identically")
        print("            bundle sha256 \(first.treeHash)")
    }

    // MARK: Tools

    private func rendererInstance() throws -> Renderer {
        if let rendererCache { return rendererCache }
        let renderer = try locateRenderer(scratch: scratchURL)
        rendererCache = renderer
        return renderer
    }

    // MARK: Verify

    private func runVerify(renderer: Renderer) throws -> Bool {
        guard let palette, let artifacts else { throw IconBuildError("internal error: bundle not built") }
        let log = CheckLog()

        log.section("verify — sources & generated bundle")
        log.pass("palette.json", "generation \(palette.designGeneration) · \(palette.fillType) document fill · \(palette.groups.count) groups · \(palette.layers.count) layers")
        log.pass("layer assets", "\(artifacts.assets.count) SVG\(artifacts.assets.count == 1 ? "" : "s"), no <text> elements")

        do {
            let stats = try validateManifestSchema(artifacts.manifest, expectedAssets: Set(artifacts.assets.keys))
            log.pass("icon.json schema", "\(stats.groupCount) groups · \(stats.layerCount) layers · only supported keys and colors")
            if stats.groupCount != palette.groups.count || stats.layerCount != palette.layers.count {
                log.fail("icon.json coverage", "manifest has \(stats.groupCount)/\(stats.layerCount) groups/layers, palette has \(palette.groups.count)/\(palette.layers.count)")
            } else {
                log.pass("icon.json coverage", "every palette group and layer is emitted")
            }
        } catch let error as IconBuildError {
            log.fail("icon.json schema", error.message)
            for detail in error.details { log.detail(detail) }
        }

        if bundleMatches(artifacts, at: bundleURL) {
            log.pass("bundle on disk", "Assets/ + icon.json match the regenerated bytes")
        } else {
            log.fail("bundle on disk", "\(relativePath(bundleURL, from: root)) does not match a fresh build")
        }

        let rebuilt = try makeArtifacts(palette: palette, assets: layerAssets)
        if rebuilt.manifest == artifacts.manifest && rebuilt.assets == artifacts.assets {
            log.pass("idempotent build", "two builds byte-identical · sha256 \(artifacts.treeHash)")
        } else {
            log.fail("idempotent build", "two builds of the same sources differ")
        }

        log.section("verify — ictool renditions (\(renditionPixelSize) px)")
        if renderer.shortVersion.hasPrefix("27") {
            log.pass("ictool", renderer.versionDescription)
        } else {
            log.warn("ictool", "\(renderer.versionDescription) — expected Icon Composer 27")
        }

        var analyses: [String: RenderAnalysis] = [:]
        for rendition in renditionNames {
            do {
                let analysis = try renderIcon(
                    renderer: renderer,
                    bundle: bundleURL,
                    rendition: rendition,
                    pixelSize: renditionPixelSize,
                    generation: palette.designGeneration,
                    scratch: scratchURL,
                    logName: "verify-\(rendition)")
                analyses[rendition] = analysis
                log.pass(rendition, "\(analysis.width)×\(analysis.height) · \(formattedBytes(analysis.byteCount)) · \(Int((analysis.opaqueFraction * 100).rounded()))% opaque · mean \(analysis.meanColor)")
            } catch let error as IconBuildError {
                log.fail(rendition, error.message)
                for detail in error.details { log.detail(detail) }
            } catch {
                log.fail(rendition, "\(error)")
            }
        }

        if analyses.count == renditionNames.count {
            var duplicates: [String] = []
            for firstIndex in 0..<renditionNames.count {
                for secondIndex in (firstIndex + 1)..<renditionNames.count {
                    let first = renditionNames[firstIndex]
                    let second = renditionNames[secondIndex]
                    if analyses[first]!.signature == analyses[second]!.signature {
                        duplicates.append("\(first) == \(second)")
                    }
                }
            }
            if duplicates.isEmpty {
                log.pass("rendition distinctness", "all 15 rendition pairs differ in pixels")
            } else {
                log.fail("rendition distinctness", "pixel-identical renditions: \(duplicates.joined(separator: ", ")) — fill-specializations may be ignored")
            }
            if let light = analyses["Default"], let dark = analyses["Dark"] {
                if light.signature == dark.signature {
                    log.fail("Default vs Dark", "renders are pixel-identical; per-appearance fills did not apply")
                } else {
                    log.pass("Default vs Dark", "appearance fills applied (mean \(light.meanColor) vs \(dark.meanColor))")
                }
            }
        }

        let otherGeneration = palette.designGeneration == 26 ? 27 : 26
        do {
            let baseline = try renderIcon(
                renderer: renderer,
                bundle: bundleURL,
                rendition: "Default",
                pixelSize: renditionPixelSize,
                generation: palette.designGeneration,
                scratch: scratchURL,
                logName: "verify-Default-generation\(palette.designGeneration)")
            let forcedOther = try renderIcon(
                renderer: renderer,
                bundle: bundleURL,
                rendition: "Default",
                pixelSize: renditionPixelSize,
                generation: otherGeneration,
                scratch: scratchURL,
                logName: "verify-Default-generation\(otherGeneration)")
            if baseline.signature == forcedOther.signature {
                log.fail("design generation", "Default is identical with --design-generation \(palette.designGeneration) and \(otherGeneration); ictool may be ignoring the flag")
            } else {
                log.pass("design generation", "Default renders differ for generation \(palette.designGeneration) vs \(otherGeneration)")
            }
            let unflagged = try renderIcon(
                renderer: renderer,
                bundle: bundleURL,
                rendition: "Default",
                pixelSize: renditionPixelSize,
                generation: nil,
                scratch: scratchURL,
                logName: "verify-Default-generation-default")
            if unflagged.signature == baseline.signature {
                log.pass("default generation", "ictool without --design-generation matches generation \(palette.designGeneration)")
            } else {
                log.warn("default generation", "ictool's unflagged default differs from generation \(palette.designGeneration); we always pass the flag explicitly")
            }
        } catch let error as IconBuildError {
            log.fail("design generation", error.message)
            for detail in error.details { log.detail(detail) }
        }

        log.section("verify — Xcode actool compile")
        if let actool = locateActool(scratch: scratchURL) {
            do {
                try runActoolCheck(actool: actool, log: log)
            } catch let error as IconBuildError {
                log.fail("actool compile", error.message)
                for detail in error.details { log.detail(detail) }
            }
        } else {
            log.warn("actool compile", "actool not found via xcrun — skipped Xcode consumption check")
        }

        log.section("verify — result")
        return log.result()
    }

    private func runActoolCheck(actool: URL, log: CheckLog) throws {
        let fm = FileManager.default
        let work = scratchURL.appendingPathComponent("actool")
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work.appendingPathComponent("out"), withIntermediateDirectories: true)

        // actool matches the input document by basename against --app-icon.
        let stagedBundle = work.appendingPathComponent("AppIcon.icon")
        do {
            try fm.copyItem(at: bundleURL, to: stagedBundle)
        } catch {
            throw IconBuildError("cannot stage the bundle for actool", details: [error.localizedDescription])
        }
        let output = work.appendingPathComponent("out")
        let partialInfoPlist = output.appendingPathComponent("partial-info.plist")
        let target = deploymentTarget()
        let arguments = [
            stagedBundle.path,
            "--compile", output.path,
            "--platform", "iphonesimulator",
            "--minimum-deployment-target", target,
            "--app-icon", "AppIcon",
            "--target-device", "iphone",
            "--target-device", "ipad",
            "--output-partial-info-plist", partialInfoPlist.path,
            "--warnings", "--errors", "--notices",
        ]
        let result = try runProcess(actool, arguments, scratch: scratchURL, logName: "actool")
        let stderr = result.stderrText

        var descriptions: [String] = []
        var warningDescriptions: [String] = []
        var notices = 0
        var outputFiles: [String] = []
        if let plist = try? PropertyListSerialization.propertyList(from: result.stdout, options: [], format: nil) as? [String: Any] {
            func actoolDescriptions(_ key: String) -> [String] {
                guard let array = plist[key] as? [[String: Any]] else { return [] }
                return array.compactMap { $0["description"] as? String }
            }
            descriptions = actoolDescriptions("com.apple.actool.errors")
            warningDescriptions = actoolDescriptions("com.apple.actool.warnings")
            notices = (plist["com.apple.actool.notices"] as? [[String: Any]])?.count ?? 0
            if let results = plist["com.apple.actool.compilation-results"] as? [String: Any],
               let files = results["output-files"] as? [String] {
                outputFiles = files
            }
        }

        guard result.status == 0, descriptions.isEmpty else {
            throw IconBuildError("actool rejected \(relativePath(bundleURL, from: root))", details: descriptions + (stderr.isEmpty ? [] : [stderr]))
        }
        if stderr.contains("CoreSVG has logged an error") {
            throw IconBuildError("actool: CoreSVG rejected an SVG asset", details: [stderr])
        }
        if let warning = warningDescriptions.first {
            log.warn("actool compile", warning)
        }
        let hasCar = outputFiles.contains { $0.hasSuffix("Assets.car") } || fm.fileExists(atPath: output.appendingPathComponent("Assets.car").path)
        let legacyCount = outputFiles.filter { $0.hasSuffix(".png") }.count
        log.pass("actool compile", "iOS \(target) · \(hasCar ? "Assets.car" : "no Assets.car") + \(legacyCount) legacy PNG\(legacyCount == 1 ? "" : "s") · \(notices) notice\(notices == 1 ? "" : "s")")
    }

    private func deploymentTarget() -> String {
        let pbxproj = root.appendingPathComponent("PortfolioAgent.xcodeproj/project.pbxproj")
        guard let text = try? String(contentsOf: pbxproj, encoding: .utf8) else { return "17.0" }
        for line in text.split(separator: "\n") where line.contains("IPHONEOS_DEPLOYMENT_TARGET") {
            guard let equals = line.firstIndex(of: "="), let semicolon = line.firstIndex(of: ";") else { continue }
            let value = line[line.index(after: equals)..<semicolon].trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return "17.0"
    }

    // MARK: Previews

    private func runPreviews(renderer: Renderer) throws {
        guard let palette, let artifacts else { throw IconBuildError("internal error: bundle not built") }
        let fm = FileManager.default
        let renditionsDirectory = previewsURL.appendingPathComponent("renditions")
        let ladderDirectory = previewsURL.appendingPathComponent("ladder")
        try fm.createDirectory(at: previewsURL, withIntermediateDirectories: true)
        try? fm.removeItem(at: renditionsDirectory)
        try? fm.removeItem(at: ladderDirectory)
        try fm.createDirectory(at: renditionsDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: ladderDirectory, withIntermediateDirectories: true)

        print("")
        print("previews")
        var renditionAnalyses: [String: RenderAnalysis] = [:]
        for rendition in renditionNames {
            let analysis = try renderIcon(
                renderer: renderer,
                bundle: bundleURL,
                rendition: rendition,
                pixelSize: renditionPixelSize,
                generation: palette.designGeneration,
                scratch: scratchURL,
                logName: "preview-\(rendition)")
            renditionAnalyses[rendition] = analysis
            let destination = renditionsDirectory.appendingPathComponent("\(rendition)-1024.png")
            try writePreviewPNG(from: analysis.url, to: destination)
            print("  \(padded(relativePath(destination, from: root), to: 58)) \(formattedBytes(fileSize(at: destination)))")
        }

        var ladderEntries: [(points: Int, pixels: Int, url: URL)] = []
        for points in ladderPointSizes {
            let pixels = points * ladderRasterScale
            let analysis = try renderIcon(
                renderer: renderer,
                bundle: bundleURL,
                rendition: "Default",
                pixelSize: pixels,
                generation: palette.designGeneration,
                scratch: scratchURL,
                logName: "ladder-\(points)")
            let destination = ladderDirectory.appendingPathComponent("Default-\(points)pt@\(ladderRasterScale)x.png")
            try writePreviewPNG(from: analysis.url, to: destination)
            ladderEntries.append((points, pixels, analysis.url))
            print("  \(padded(relativePath(destination, from: root), to: 58)) \(formattedBytes(fileSize(at: destination)))")
        }

        let renditionEntries: [(name: String, note: String, image: CGImage)] = try renditionNames.map { name in
            let url = renditionsDirectory.appendingPathComponent("\(name)-1024.png")
            return (name, renditionNotes[name] ?? "", try loadPreviewImage(at: url))
        }
        let renditionsSheet = previewsURL.appendingPathComponent("icon-renditions-1024.png")
        try composeRenditionsSheet(entries: renditionEntries, generation: palette.designGeneration, to: renditionsSheet)
        print("  \(padded(relativePath(renditionsSheet, from: root), to: 58)) \(formattedBytes(fileSize(at: renditionsSheet)))")

        let ladderImages: [(points: Int, pixels: Int, image: CGImage)] = try ladderEntries.map { entry in
            (entry.points, entry.pixels, try loadPreviewImage(at: entry.url))
        }
        let ladderSheet = previewsURL.appendingPathComponent("icon-size-ladder.png")
        try composeLadderSheet(entries: ladderImages, generation: palette.designGeneration, to: ladderSheet)
        print("  \(padded(relativePath(ladderSheet, from: root), to: 58)) \(formattedBytes(fileSize(at: ladderSheet)))")

        _ = artifacts
    }

    /// Writes a preview PNG as an 8-bit sRGB file. ictool emits 16-bit renders that are
    /// roughly twice the size; previews are for human review, while --verify always
    /// inspects the raw ictool output.
    private func writePreviewPNG(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: source),
              let representation = NSBitmapImageRep(data: data),
              let image = representation.cgImage else {
            throw IconBuildError("cannot re-encode preview \(source.lastPathComponent)")
        }
        let width = representation.pixelsWide
        let height = representation.pixelsHigh
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw IconBuildError("cannot re-encode preview \(source.lastPathComponent)")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let rendered = context.makeImage(),
              let encoded = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else {
            throw IconBuildError("cannot re-encode preview \(source.lastPathComponent)")
        }
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoded.write(to: destination, options: .atomic)
        } catch {
            throw IconBuildError("cannot write \(destination.path)", details: [error.localizedDescription])
        }
    }
}

// MARK: - Entry point

func runMain() throws {
    let options = try parseOptions(CommandLine.arguments)
    if options.showHelp {
        print(Options.usage)
        return
    }
    try App(options: options).run()
}

do {
    try runMain()
} catch let error as IconBuildError {
    FileHandle.standardError.write(("error: \(error.message)\n").data(using: .utf8)!)
    for detail in error.details {
        FileHandle.standardError.write(("  \(detail)\n").data(using: .utf8)!)
    }
    exit(1)
} catch {
    FileHandle.standardError.write(("error: \(error)\n").data(using: .utf8)!)
    exit(1)
}
