#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint zebrautil.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'zebrautil'
  s.version          = '0.0.1'
  s.summary          = 'A Flutter plugin for working with Zebra label printers (Bluetooth/MFi/Wi-Fi).'
  s.description      = <<-DESC
A Flutter plugin for discovering and printing to Zebra label printers
over Bluetooth (MFi) and Wi-Fi (TCP), with helpers for ZPL/CPCL.
                       DESC
  s.homepage         = 'https://github.com/ovidiuomniaz/zebra_printer_utility'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'ovidiuomniaz' => 'ovidiu@omniaz.io' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.dependency 'CocoaAsyncSocket', '~> 7.6'
  s.platform = :ios, '13.0'

  s.static_framework = true

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  # System frameworks linked from the iOS SDK (no longer vendored as header stubs).
  s.frameworks = 'ExternalAccessory', 'QuartzCore'

  # Zebra Link-OS Multiplatform SDK static archive.
  # Vendored because Zebra distributes the iOS SDK only via their developer
  # portal (not CocoaPods/SPM). SHA-256 recorded in docs/VENDORED.md.
  s.preserve_paths = 'libZSDK_API.a'
  s.xcconfig = { 'OTHER_LDFLAGS' => '-lZSDK_API' }
  s.vendored_libraries = 'libZSDK_API.a'
end
