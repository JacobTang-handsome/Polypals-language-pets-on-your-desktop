#!/usr/bin/env ruby
# Synchronize static Simplified Chinese Swift literals into Localizable.xcstrings.
# Interpolated strings are intentionally skipped because Xcode assigns typed
# format placeholders to those at compile time.
require "json"

root = File.expand_path("..", __dir__)
catalog_path = File.join(root, "Sources/PolyPals/Resources/Localizable.xcstrings")
catalog = JSON.parse(File.read(catalog_path))
strings = catalog["strings"] ||= {}

Dir.glob(File.join(root, "Sources/PolyPals/**/*.swift")).sort.each do |path|
  File.read(path).scan(/"((?:\\.|[^"\\])*)"/) do |match|
    encoded = match.first
    next if encoded.include?("\\(")
    begin
      value = JSON.parse(%Q{"#{encoded}"})
    rescue JSON::ParserError
      next
    end
    next unless value.match?(/\p{Han}/)
    strings[value] ||= {
      "localizations" => {
        "zh-Hans" => {
          "stringUnit" => { "state" => "translated", "value" => value }
        }
      }
    }
  end
end

catalog["strings"] = strings.sort.to_h
File.write(catalog_path, JSON.pretty_generate(catalog) + "\n")
puts "Synchronized #{strings.count} Simplified Chinese strings."
