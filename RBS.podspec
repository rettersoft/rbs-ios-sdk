#
# Be sure to run `pod lib lint RBS.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'RBS'
  s.version          = '0.3.0'
  s.summary          = 'RBS iOS SDK.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/rettersoft/rbs-ios-sdk'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'baranbaygan' => 'baran@rettermobile.com' }
  s.source           = { :git => 'https://github.com/rettersoft/rbs-ios-sdk.git', :tag => 'main' }
  # s.version.to_s
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '10.0'

  s.source_files = 'RBS/Classes/**/*'
  
  # s.resource_bundles = {
  #   'RBS' => ['RBS/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
#  s.frameworks = 'CommonCrypto'
  # s.dependency 'AFNetworking', '~> 2.3'
  
  s.dependency 'Moya/RxSwift', '~> 14.0'
  s.dependency 'RxSwift', '~> 5'
  s.dependency 'Alamofire', '~> 5.2'
  s.dependency 'ObjectMapper', '~> 3.4'
  s.dependency 'KeychainSwift', '~> 19.0'
  s.dependency 'JWTDecode', '~> 2.4'
  
end
