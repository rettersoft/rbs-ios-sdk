// swift-tools-version:5.2
import PackageDescription
let package = Package(
    name: "RBS",
    platforms: [.macOS(.v10_12),
                .iOS(.v11),
                .tvOS(.v10),
                .watchOS(.v3)],
    products: [
        .library(name: "RBS", targets: ["RBS"])
    ],
    dependencies: [
        .package(url: "https://github.com/Moya/Moya.git", .upToNextMajor(from: "14.0.0")),
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.2.0")),
        .package(url: "https://github.com/tristanhimmelman/ObjectMapper.git", .upToNextMajor(from: "4.1.0")),
        .package(url: "https://github.com/datatheorem/TrustKit.git", .upToNextMajor(from: "1.6.5")),
        .package(name: "KeychainSwift", url: "https://github.com/evgenyneu/keychain-swift.git", .upToNextMajor(from: "19.0.0")),
        .package(name: "JWTDecode", url: "https://github.com/auth0/JWTDecode.swift.git", .upToNextMajor(from: "2.6.0"))
    ],
    targets: [
        .target(name: "RBS", dependencies: [
            "Moya", "Alamofire", "ObjectMapper", "KeychainSwift", "JWTDecode", "TrustKit"
        ], path: "RBS/Classes")
    ]
)
