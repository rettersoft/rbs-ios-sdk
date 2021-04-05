// swift-tools-version:5.2
import PackageDescription
let package = Package(
    name: "RBS",
    products: [
        .library(name: "RBS", targets: ["RBS"])
    ],
    dependencies: [
        .package(url: "https://github.com/Moya/Moya.git", .upToNextMajor(from: "14.0.0")),
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.2.0")),
        .package(url: "https://github.com/tristanhimmelman/ObjectMapper.git", .upToNextMajor(from: "4.1.0")),
        .package(url: "https://github.com/evgenyneu/keychain-swift.git", from: "19.0.0"),
        .package(url: "https://github.com/auth0/JWTDecode.swift.git", from: "2.6.0")
        
    ],
    targets: [
        .target(name: "RBS", path: "RBS/Classes")
    ]
)
