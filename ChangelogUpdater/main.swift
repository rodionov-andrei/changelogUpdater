//
//  main.swift
//  ChangelogUpdater
//
//  Created by Andrey Rodionov on 21/11/2018.
//  Copyright © 2018 Mezzo. All rights reserved.
//

import Foundation

extension String {
    func deletePrefix(_ prefix: String) -> String {
        guard self.hasPrefix(prefix) else { return self }
        return String(self.dropFirst(prefix.count))
    }

    func deleteSuffix(_ suffix: String) -> String {
        guard self.hasSuffix(suffix) else { return self }
        return String(self.dropLast(suffix.count))
    }

    func matches(_ regex: String) -> Bool {
        return self.range(of: regex, options: .regularExpression, range: nil, locale: nil) != nil
    }
}

struct Options {
    static let dateFormat = "yyyy-MM-dd"
    static let versionPattern = "[0-9]{3}.[0-9].[0-9]"
    static let changelogFilename = "CHANGELOG.md"

    /*to find ## [Unreleased]*/
    static let uniqueLettersToFindUnreleasedSection = "## [Unreleased]"
    /*to find [Unreleased]: https://src.sibext.com/ios/mezzo/compare/v229.4.1...HEAD */
    static let uniqueLettersToFindComparisonSection = "[Unreleased]:"

    /* must be > 0, version is last */
    static let commandLineTotalArguments = 2
}

let arguments = CommandLine.arguments
guard arguments.count == Options.commandLineTotalArguments,
      let newVersion = arguments.last, newVersion.matches(Options.versionPattern) else {
    fatalError("Invalid version format. Please enter version in format 229.0.1")
}

var currentDate: String {
    let formatter = DateFormatter()
    formatter.dateFormat = Options.dateFormat
    return formatter.string(from: Date())
}

guard let currentDirURL = URL(string: FileManager.default.currentDirectoryPath) else {
    fatalError("Can't transform current directory to URL")
}

let pathToChangelog = currentDirURL.absoluteString + "/" + Options.changelogFilename
let changelogURL = URL(fileURLWithPath: pathToChangelog)
guard let changelogContent = try? String(contentsOfFile: pathToChangelog) else {
    fatalError("File not found: \(pathToChangelog)")
}
let changelogContentElements = changelogContent.components(separatedBy: "\n")

/*
 Insert new tag name for changes in unreleased section
 < ...
 ## [Unreleased]
 ### Fixed
 - Bla bla
 ... >
 */
func modifyUnreleasedSection(_ changelogContent: [String]) -> [String] {
    let indexOfUnreleased = changelogContent.firstIndex { $0 == Options.uniqueLettersToFindUnreleasedSection }
    guard let index = indexOfUnreleased else {
        fatalError("Unreleased section not found")
    }
    var output = changelogContent
    output.insert("", at: index + 1)
    output.insert("## [" + newVersion + "] - " + currentDate, at: index + 2)
    if output[index + 3].isEmpty {
        output.remove(at: index + 3)
    }
    return output
}

/*
 Modifying part of changelog where links to compare versions are stored.
< ...
[Unreleased]: https://src.sibext.com/ios/mezzo/compare/v229.4.1...HEAD       // marked as toModify1
[229.4.1]: https://src.sibext.com/ios/mezzo/compare/v229.2.2...v229.4.1      // marked as toModify2
 ... >
 */
func modifyComparisonSection(_ changelogContent: [String]) -> [String] {
    let toModify1IndexWeak = changelogContent.firstIndex { $0.contains(Options.uniqueLettersToFindComparisonSection) }
    guard let toModify1Index = toModify1IndexWeak else {
        fatalError("Comparison section not found")
    }
    let toModify2Index = toModify1Index + 1
    var output = changelogContent
    let toModify1 = output[toModify1Index]
    let toModify2 = output[toModify2Index]

    guard let regex = try? NSRegularExpression(pattern: Options.versionPattern) else {
        fatalError("Invalid version pattern")
    }
    guard let oldVersionCheckResult = regex.firstMatch(in: toModify1, range: NSRange(toModify1.startIndex...,
                                                                          in: toModify1)) else {
        fatalError("Comparison section: old version not found by regex")
    }
    let oldVersion = String(toModify1[Range(oldVersionCheckResult.range, in: toModify1)!])

    let modified1 = regex.stringByReplacingMatches(in: toModify1, range: NSRange(location: 0,
                                                   length: toModify1.lengthOfBytes(using: .utf8)),
                                                   withTemplate: newVersion)

    var modified2 = toModify2.replacingOccurrences(of: oldVersion, with: newVersion)
    guard let cutOfVersions = modified2.components(separatedBy: "/v").first else {
        fatalError("Incorrect comparison section")
    }
    modified2 = cutOfVersions
    modified2 += "/v" + oldVersion + "..." + "v" + newVersion

    output.remove(at: toModify1Index)
    output.insert(modified1, at: toModify1Index)
    output.remove(at: toModify2Index)
    output.insert(modified2, at: toModify2Index)

    return output
}

let modifiedUnreleased = modifyUnreleasedSection(changelogContentElements)
let modifiedComparison = modifyComparisonSection(modifiedUnreleased)
let output = modifiedComparison.joined(separator: "\n")

do {
    try output.write(to: changelogURL, atomically: true, encoding: .utf8)
} catch {
    fatalError(error.localizedDescription)
}
