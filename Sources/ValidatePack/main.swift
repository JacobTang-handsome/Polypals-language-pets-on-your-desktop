import Foundation
import PolyPalsPluginKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: validate-pack <Example.polypals-pack>\n".utf8))
    exit(64)
}
let report = PluginPackValidator().validate(directory: URL(fileURLWithPath: CommandLine.arguments[1]))
for issue in report.issues {
    print("\(issue.severity.rawValue.uppercased()) \(issue.code)\(issue.path.map { " [\($0)]" } ?? ""): \(issue.message)")
}
if report.isValid { print("VALID \(report.manifest?.id ?? "pack")") }
exit(report.isValid ? 0 : 1)
