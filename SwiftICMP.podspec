Pod::Spec.new do |spec|

  spec.name         = "SwiftICMP"
  spec.version      = "0.0.1"
  spec.summary      = "Swift ICMPv4 sender"
  spec.description  = <<-DESC
Swift ICMPv4 sender iOS 15.0+ macOS 12.0+ tvOS 15.0+ watchOS 8.0+
DESC
  spec.homepage     = "https://github.com/mob-connection/SwiftICMP"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "mob-connection" => "ozhurbaiosdevelop@gmail.com" }

  spec.ios.deployment_target = "15.0"
  spec.osx.deployment_target = '12.0'
  spec.tvos.deployment_target = '15.0'
  spec.watchos.deployment_target = '8.0'

  spec.swift_version = "5.5"
  spec.source = { :git => "https://github.com/mob-connection/SwiftICMP.git", :tag => "#{spec.version}" }
  spec.source_files  = "Sources/**/*.swift"
  spec.resource_bundles = {'Sources' => ['Sources/PrivacyInfo.xcprivacy']}

end
