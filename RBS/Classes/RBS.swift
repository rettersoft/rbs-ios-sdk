
import Alamofire
import Moya
import KeychainSwift
import ObjectMapper
import JWTDecode
import Foundation
import TrustKit
import FirebaseCore
import FirebaseFirestore
import FirebaseAuth

public enum RbsRegion {
    case euWest1, euWest1Beta
    
    var getUrl:String {
        switch self {
        case .euWest1: return "https://root.api.rtbs.io"
        case .euWest1Beta: return "https://root.test-api.rtbs.io"
        }
    }
    
    
    var postUrl:String {
        switch self {
        case .euWest1: return "https://root.api.rtbs.io"
        case .euWest1Beta: return "https://root.test-api.rtbs.io"
        }
    }
    
    var apiURL: String {
        switch self {
        case .euWest1:
            return "api.rtbs.io"
        case .euWest1Beta:
            return "test-api.rtbs.io"
        }
    }
}

public struct RBSConfig {
    var projectId: String?
    var secretKey: String?
    var developerId: String?
    var serviceId: String?
    var region: RbsRegion?
    var sslPinningEnabled: Bool?
    var isLoggingEnabled: Bool?
    
    public init(
        projectId: String,
        secretKey: String? = nil,
        developerId: String? = nil,
        serviceId: String? = nil,
        region: RbsRegion? = nil,
        sslPinningEnabled: Bool? = nil,
        isLoggingEnabled: Bool = false
    ) {
        
        self.projectId = projectId
        self.secretKey = secretKey
        self.developerId = developerId
        self.serviceId = serviceId
        self.region = region == nil ? .euWest1 : region
        self.sslPinningEnabled = sslPinningEnabled
        self.isLoggingEnabled = isLoggingEnabled
    }
}

struct RBSLogger {
    let isLoggingEnabled: Bool
    
    func log(_ text: Any) {
        if isLoggingEnabled {
            print(text)
        }
    }
}

public struct RBSUser {
    public var uid: String
    public var isAnonymous: Bool
}

struct RBSTokenResponse: Decodable {
    var response: RBSTokenData
}

struct RBSTokenData: Mappable, Decodable {
    var projectId: String?
    var isAnonym: Bool?
    var uid: String?
    var accessToken: String?
    var refreshToken: String?
    var firebaseToken: String?
    var firebase: CloudOption?
    
    var accessTokenExpiresAt: Date? {
        get {
            guard let accessToken = self.accessToken else { return nil }
            
            let jwt = try! decode(jwt: accessToken)
            return jwt.expiresAt
        }
    }
    
    var refreshTokenExpiresAt: Date? {
        get {
            guard let token = self.refreshToken else { return nil }
            
            let jwt = try! decode(jwt: token)
            return jwt.expiresAt
        }
    }
    
    var userId: String? {
        if let token = accessToken {
            let jwt = try! decode(jwt: token)
            guard let id = jwt.claim(name: "userId").string else {
                return nil
            }
            
            return id
        }
        return nil
    }
    
    
    init?(map: Map) {
        
    }
    
    mutating func mapping(map: Map) {
        isAnonym <- map["isAnonym"]
        projectId <- map["projectId"]
        uid <- map["uid"]
        accessToken <- map["accessToken"]
        refreshToken <- map["refreshToken"]
        firebaseToken <- map["firebaseToken"]
    }
}

public enum RBSClientAuthStatus {
    case signedIn(user: RBSUser),
         signedInAnonymously(user: RBSUser),
         signedOut,
         authenticating
}

public enum RBSCulture: String {
    case en = "en-US",
         tr = "tr-TR"
}

public protocol RBSClientDelegate {
    func rbsClient(client: RBS, authStatusChanged toStatus: RBSClientAuthStatus)
}

enum RBSKeychainKey {
    case token
    
    var keyName: String {
        get {
            switch self {
            case .token: return "io.rtbs.token"
            }
        }
    }
}

public enum RBSError: Error {
    case TokenError,
         cloudNotConfigured,
         classIdRequired,
         cloudObjectNotFound,
         methodReturnedError,
         parsingError,
         firebaseInitError
}

extension String: LocalizedError {
    public var errorDescription: String? { return self }
}

class RBSAction {
    var tokenData: RBSTokenData?
    
    var successCompletion: ((_ result: [Any]) -> Void)?
    var errorCompletion: ((_ error: Error) -> Void)?
    var action: String?
    var data: [String: Any]?
    
    init() { }
}

public class RBS {
    var projectId: String!
    
    let serialQueue = DispatchQueue(label: "com.queue.Serial")
    
    let semaphore = DispatchSemaphore(value: 0)
    let firebaseAuthSemaphore = DispatchSemaphore(value: 0)
    
    private var cloudObjects: [RBSCloudObject] = []
    
    public var delegate: RBSClientDelegate? {
        didSet {
            
            // Check token data and raise status update
            if let data = self.keychain.getData(RBSKeychainKey.token.keyName) {
                let json = try! JSONSerialization.jsonObject(with: data, options: [])
                
                if let tokenData = Mapper<RBSTokenData>().map(JSONObject: json),
                   let accessToken = tokenData.accessToken {
                    
                    let jwt = try! decode(jwt: accessToken)
                    if let userId = jwt.claim(name: "userId").string, let anonymous = jwt.claim(name: "anonymous").rawValue as? Bool {
                        
                        // User has changed.
                        let user = RBSUser(uid: userId, isAnonymous: anonymous)
                        
                        if anonymous {
                            self.delegate?.rbsClient(client: self, authStatusChanged: .signedInAnonymously(user: user))
                        } else {
                            self.delegate?.rbsClient(client: self, authStatusChanged: .signedIn(user: user))
                        }
                    } else {
                        self.delegate?.rbsClient(client: self, authStatusChanged: .signedOut)
                    }
                } else {
                    self.delegate?.rbsClient(client: self, authStatusChanged: .signedOut)
                }
            } else {
                self.delegate?.rbsClient(client: self, authStatusChanged: .signedOut)
            }
            
        }
    }
    
    var _service: MoyaProvider<RBSService>?
    var service : MoyaProvider<RBSService> {
        get {
            if self._service != nil {
                return self._service!
            }
            
            let accessTokenPlugin = AccessTokenPlugin { _ -> String in
                if let data = self.keychain.getData(RBSKeychainKey.token.keyName) {
                    let json = try! JSONSerialization.jsonObject(with: data, options: [])
                    if let tokenData = Mapper<RBSTokenData>().map(JSONObject: json), let accessToken = tokenData.accessToken {
                        return accessToken
                    }
                }
                return ""
            }
            var plugins: [PluginType] = [CachePolicyPlugin(), accessTokenPlugin]
            if config.isLoggingEnabled ?? false {
                plugins.append(NetworkLoggerPlugin())
            }
            self._service = MoyaProvider<RBSService>(plugins: plugins)
            
            return self._service!
        }
    }
    
    let keychain = KeychainSwift()
    
    var config: RBSConfig!
    
    private var firebaseApp: FirebaseApp?
    fileprivate var db: Firestore?
    
    private let logger: RBSLogger
    
    public init(config: RBSConfig) {
        self.logger = RBSLogger(isLoggingEnabled: config.isLoggingEnabled ?? false)
        if let sslPinningEnabled = config.sslPinningEnabled, sslPinningEnabled == false {
            // Dont enable ssl pinning
            logger.log("WARNING! RBS SSL Pinning disabled.")
        } else {
            self.setupTrustKit()
        }
        
        
        let firebaseOptions = FirebaseOptions(googleAppID: "1:814752823492:ios:6429462157e997a146f191",
                                              gcmSenderID: "814752823492")
        firebaseOptions.projectID = "rtbs-c82e1"
        firebaseOptions.apiKey = "AIzaSyCYKQHVjql92jRX350a7dEaxQUhgkSxiUE"
        
        FirebaseApp.configure(name: "rbs", options: firebaseOptions)
        
        guard let app = FirebaseApp.app(name: "rbs") else {
            fatalError()
        }
        
        self.firebaseApp = app
        self.db = Firestore.firestore(app: app)
        
        self.config = config
        self.projectId = config.projectId
        globalRbsRegion = config.region!
    }
    
    private var safeNow: Date {
        get {
            return Date(timeIntervalSinceNow: 30)
        }
    }
    
    // MARK: - Private methods
    
    private func setupTrustKit() {
        let pinningConfig: [String : Any] = [
            kTSKEnforcePinning: true,
            kTSKIncludeSubdomains: true,
            kTSKExpirationDate: "2025-12-01",
            kTSKPublicKeyHashes: [
                "++MBgDH5WGvL9Bcn5Be30cRcL0f5O+NyoXuWtQdX1aI=",
                "f0KW/FtqTjs108NpYj42SrGvOB2PpxIVM8nWxjPqJGE=",
                "NqvDJlas/GRcYbcWE8S/IceH9cq77kg0jVhZeAPXq8k=",
                "9+ze1cZgR9KO1kZrVDxA4HQ6voHRCSVNz4RdTCx4U8U=",
                "KwccWaCgrnaw6tsrrSO61FgLacNgG2MMLq8GE6+oP5I=",
                "FfFKxFycfaIz00eRZOgTf+Ne4POK6FgYPwhBDqgqxLQ="
            ]
        ]
        let trustKitConfig = [
            kTSKSwizzleNetworkDelegates: false,
            kTSKPinnedDomains: [
                "core.rtbs.io": pinningConfig,
                "core-test.rettermobile.com": pinningConfig,
                "core-test.rtbs.io": pinningConfig,
                "core-internal.rtbs.io": pinningConfig,
                "core-internal-beta.rtbs.io": pinningConfig
                
            ]
        ] as [String: Any]
        
        TrustKit.setLoggerBlock { (_) in }
        TrustKit.initSharedInstance(withConfiguration: trustKitConfig)
    }
    
    private func getTokenData() throws -> RBSTokenData {
        logger.log("getTokenData called")
        
        let now = self.safeNow
        
        if let data = self.keychain.getData(RBSKeychainKey.token.keyName) {
            
            let json = try! JSONSerialization.jsonObject(with: data, options: [])
            
            if let tokenData = Mapper<RBSTokenData>().map(JSONObject: json),
               let refreshToken = tokenData.refreshToken,
               let refreshTokenExpiresAt = tokenData.refreshTokenExpiresAt,
               let accessTokenExpiresAt = tokenData.accessTokenExpiresAt,
               let projectId = tokenData.projectId {
                
                if(projectId == self.projectId) {
                    logger.log("refreshTokenExpiresAt \(refreshTokenExpiresAt)")
                    logger.log("accessTokenExpiresAt \(accessTokenExpiresAt)")
                    if refreshTokenExpiresAt > now && accessTokenExpiresAt > now {
                        // Token can be used
                        logger.log("DEBUG111 returning tokenData")
                        return tokenData
                    }
                    
                    if refreshTokenExpiresAt > now && accessTokenExpiresAt < now {
                        logger.log("DEBUG111 refreshing token")
                        // DO REFRESH
                        let refreshTokenRequest = RefreshTokenRequest()
                        refreshTokenRequest.refreshToken = refreshToken
                        
                        return try self.refreshToken(tokenData: tokenData)
                    }
                }
            }
        }
        
        // Get anonym token
        return try self.getAnonymToken()
    }
    
    private func saveTokenData(tokenData: RBSTokenData?) {
        logger.log("DEBUG111 saveTokenData called with tokenData")
        var storedUserId: String? = nil
        // First get last stored token data from keychain.
        if let data = self.keychain.getData(RBSKeychainKey.token.keyName) {
            let json = try! JSONSerialization.jsonObject(with: data, options: [])
            if let storedTokenData = Mapper<RBSTokenData>().map(JSONObject: json), let accessToken = storedTokenData.accessToken {
                let jwt = try! decode(jwt: accessToken)
                if let userId = jwt.claim(name: "userId").string {
                    storedUserId = userId
                }
            }
        }
        
        guard let tokenData = tokenData else {
            
            if storedUserId != nil {
                DispatchQueue.main.async {
                    self.delegate?.rbsClient(client: self, authStatusChanged: .signedOut)
                }
            }
            
            self.keychain.delete(RBSKeychainKey.token.keyName)
            
            return
        }
        
        let obj = Mapper<RBSTokenData>().toJSON(tokenData)
        let data = try! JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted)
        self.keychain.set(data, forKey: RBSKeychainKey.token.keyName)
        
        logger.log("DEBUG111 saveTokenData 2")
        
        if let accessToken = tokenData.accessToken {
            let jwt = try! decode(jwt: accessToken)
            if let userId = jwt.claim(name: "userId").string, let anonymous = jwt.claim(name: "anonymous").rawValue as? Bool {
                
                if userId != storedUserId {
                    logger.log("DEBUG111 userId \(userId) - stored: \(storedUserId)")
                    // User has changed.
                    let user = RBSUser(uid: userId, isAnonymous: anonymous)
                    
                    cloudObjects.forEach { object in
                        object.state?.removeListeners()
                    }
                    
                    cloudObjects.removeAll()
                    
                    logger.log("DEBUG111 initFirebaseApp 1")
                    if let app = self.firebaseApp, let customToken = tokenData.firebase?.customToken {
                        self.logger.log("DEBUG111 FIREBASE custom auth \(userId)")
                       
                        Auth.auth(app: app).signIn(withCustomToken: customToken) { [weak self] (resp, error)  in
                            self?.logger.log("DEBUG111 FIREBASE custom auth COMPLETE user: \(resp?.user)")
                            self?.firebaseAuthSemaphore.signal()
                        }
                        
                        _ = self.firebaseAuthSemaphore.wait(wallTimeout: .distantFuture)
                    }
                    
                    DispatchQueue.main.async {
                        if anonymous {
                            self.delegate?.rbsClient(client: self, authStatusChanged: .signedInAnonymously(user: user))
                        } else {
                            self.delegate?.rbsClient(client: self, authStatusChanged: .signedIn(user: user))
                        }
                    }
                    
                }
                
                
            }
        }
    }
    
    private func getAnonymToken() throws -> RBSTokenData {
        logger.log("getAnonymToken called")
        
        let getAnonymTokenRequest = GetAnonymTokenRequest()
        getAnonymTokenRequest.projectId = self.config.projectId
        
        var retVal: RBSTokenData? = nil
        
        self.service.request(.getAnonymToken(request: getAnonymTokenRequest)) { [weak self] result in
            switch result {
            case .success(let response):
                let resp = try! response.map(RBSTokenResponse.self)
                retVal = resp.response
            default:
                break
            }
            self?.semaphore.signal()
        }
        _ = self.semaphore.wait(wallTimeout: .distantFuture)
        
        retVal?.projectId = self.config.projectId
        retVal?.isAnonym = true
        
        if let r = retVal {
            return r
        }
        throw "Can't get anonym token"
    }
    
    private func refreshToken(tokenData: RBSTokenData) throws -> RBSTokenData {
        logger.log("refreshToken called")
        
        let refreshTokenRequest = RefreshTokenRequest()
        refreshTokenRequest.refreshToken = tokenData.refreshToken
        refreshTokenRequest.projectId = projectId
        refreshTokenRequest.userId = tokenData.userId
        
        var retVal:RBSTokenData? = nil
        
        self.service.request(.refreshToken(request: refreshTokenRequest)) {
            [weak self] result in
            switch result {
            case .success(let response):
                retVal = try! response.map(RBSTokenData.self)
                break
            default:
                break
            }
            self?.semaphore.signal()
        }
        _ = self.semaphore.wait(wallTimeout: .distantFuture)
        
        retVal?.projectId = tokenData.projectId
        retVal?.isAnonym = tokenData.isAnonym
        
        if let r = retVal {
            return r
        }
        throw "Can't refresh token"
    }
    
    private func executeAction(
        tokenData: RBSTokenData,
        action: String,
        data: [String: Any],
        culture: String?,
        headers: [String: String]?,
        cloudObjectOptions: RBSCloudObjectOptions? = nil
    ) throws -> [Any] {
        logger.log("executeAction called")
        let req = ExecuteActionRequest()
        req.projectId = self.projectId
        req.accessToken = tokenData.accessToken
        req.actionName = action
        req.payload = data
        req.headers = headers
        req.culture = culture
        req.classID = cloudObjectOptions?.classID
        req.instanceID = cloudObjectOptions?.instanceID
        req.keyValue = cloudObjectOptions?.keyValue
        req.httpMethod = cloudObjectOptions?.httpMethod
        req.method = cloudObjectOptions?.method
        
        var errorResponse: BaseErrorResponse?
        
        var retVal: [Any]? = nil
        let semaphoreLocal = DispatchSemaphore(value: 0)
        self.service.request(.executeAction(request: req)) { result in
            switch result {
            case .success(let response):
                if (200...299).contains(response.statusCode) {
                    if cloudObjectOptions != nil {
                        retVal = [RBSCloudObjectResponse(statusCode: response.statusCode,
                                                         headers: response.response?.headers.dictionary,
                                                         body: response.data)]
                    } else {
                        if let json = try? JSONSerialization.jsonObject(with: response.data, options: []) as? [Any] {
                            retVal = json
                        } else if let json = try? JSONSerialization.jsonObject(with: response.data, options: []) {
                            retVal = [json]
                        }
                        
                        if retVal == nil {
                            retVal = []
                        }
                    }
                } else {
                    errorResponse = try? response.map(BaseErrorResponse.self)
                    errorResponse?.httpStatusCode = response.statusCode
                    
                    errorResponse?.cloudObjectResponse = cloudObjectOptions != nil ? RBSCloudObjectResponse(statusCode: response.statusCode,
                                                                                                            headers: response.response?.headers.dictionary,
                                                                                                            body: response.data) : nil
                    
                    if errorResponse == nil {
                        errorResponse = BaseErrorResponse()
                        errorResponse?.httpStatusCode = response.statusCode
                        errorResponse?.cloudObjectResponse = cloudObjectOptions != nil ? RBSCloudObjectResponse(statusCode: response.statusCode,
                                                                                                                headers: response.response?.headers.dictionary,
                                                                                                                body: response.data) : nil
                    }
                }
                break
            case .failure(let f):
                self.logger.log(f)
                break
            }
            semaphoreLocal.signal()
        }
        _ = semaphoreLocal.wait(wallTimeout: .distantFuture)
        
        if let e = errorResponse {
            throw e
        }
        if let r = retVal {
            return r
        }
        
        // Işıl & Arda & Efe
        
        throw "Can't execute action."
    }
    
    // MARK: - Public methods
    
    public func authenticateWithCustomToken(_ customToken: String) {
        logger.log("authenticateWithCustomToken called")
        serialQueue.async {
            
            self.saveTokenData(tokenData: nil)
            let req = AuthWithCustomTokenRequest()
            req.customToken = customToken
            
            let jwt = try! decode(jwt: customToken)
            guard let id = jwt.claim(name: "userId").string else {
                return
            }
            
            req.userId = id
            req.projectId = self.projectId
            
            self.service.request(.authWithCustomToken(request: req)) { [weak self] result in
                switch result {
                case .success(let response):
                    var tokenData = try! response.map(RBSTokenData.self)
                    tokenData.projectId = self?.config.projectId
                    tokenData.isAnonym = false
                    self?.serialQueue.async {
                        self?.saveTokenData(tokenData: tokenData)
                    }
                    break
                default:
                    break
                }
                self?.semaphore.signal()
            }
            _ = self.semaphore.wait(wallTimeout: .distantFuture)
            
        }
    }
    
    public func signInAnonymously() {
        send(
            action: "signInAnonym",
            data: [:],
            headers: nil) { _ in }
            onError: { _ in }
    }
    
    public func signOut() {
        
        if let data = self.keychain.getData(RBSKeychainKey.token.keyName),
           let json = try? JSONSerialization.jsonObject(with: data, options: []) {
            
            if let tokenData = Mapper<RBSTokenData>().map(JSONObject: json),
               let accessToken = tokenData.accessToken,
               let userId = tokenData.userId {
                
                let req = SignOutRequest()
                req.accessToken = accessToken
                req.projectId = projectId
                req.userId = userId
                
                self.service.request(.signout(request: req)) { result in
                    switch result {
                    case .success(_):
                        break
                    default:
                        break
                    }
                }
            }
        }
        
        
        self.saveTokenData(tokenData: nil)
        do {
            cloudObjects.forEach { object in
                object.state?.removeListeners()
            }
            cloudObjects.removeAll()
            
            guard let app = firebaseApp else {
                return
            }
            try Auth.auth(app: app).signOut()
        } catch { }
    }
    
    public func removeAllCloudObjects() { // ONLY FOR TEST PURPOSES
        cloudObjects.forEach { object in
            object.state?.removeListeners()
        }
        cloudObjects.removeAll()
    }
    
    public func generatePublicGetActionUrl(
        action actionName: String,
        data: [String: Any]
    ) -> String {
        
        let req = ExecuteActionRequest()
        req.projectId = self.projectId
        req.actionName = actionName
        req.payload = data
        
        let s: RBSService = .executeAction(request: req)
        
        var url = "\(s.baseURL)\(s.endPoint)?"
        for param in s.urlParameters {
            url = "\(url)\(param.key)=\(param.value)&"
        }
        
        return url
    }
    
    public func generateGetActionUrl(
        action actionName: String,
        data: [String: Any],
        onSuccess: @escaping (_ result: String) -> Void,
        onError: @escaping (_ error: Error) -> Void
    ) {
        serialQueue.async {
            do {
                let tokenData = try self.getTokenData()
                self.saveTokenData(tokenData: tokenData)
                
                let req = ExecuteActionRequest()
                req.projectId = self.projectId
                req.accessToken = tokenData.accessToken
                req.actionName = actionName
                req.payload = data
                
                let s: RBSService = .executeAction(request: req)
                
                var url = "\(s.baseURL)\(s.endPoint)?"
                for param in s.urlParameters {
                    url = "\(url)\(param.key)=\(param.value)&"
                }
                
                DispatchQueue.main.async {
                    onSuccess(url)
                }
                
            } catch {
                
            }
        }
    }
    
    public func send(
        action actionName: String,
        data: [String: Any],
        headers: [String: String]?,
        culture: RBSCulture? = nil,
        cloudObjectOptions: RBSCloudObjectOptions? = nil,
        onSuccess: @escaping (_ result: [Any]) -> Void,
        onError: @escaping (_ error: Error) -> Void
    ) {
        logger.log("send called")
        
        serialQueue.async {
            self.logger.log("DEBUG111 send called in async block")
            do {
                
                self.logger.log("DEBUG111 getTokenData called in send")
                let tokenData = try self.getTokenData()
                
                self.logger.log("DEBUG111 saveTokenData called in send")
                self.saveTokenData(tokenData: tokenData)
                
                if actionName == "signInAnonym" {
                    onSuccess([])
                    return
                }
                
                DispatchQueue.global().async {
                    do {
                        let actionResult = try self.executeAction(
                            tokenData: tokenData,
                            action: actionName,
                            data: data,
                            culture: culture?.rawValue,
                            headers: headers,
                            cloudObjectOptions: cloudObjectOptions
                        )
                        
                        DispatchQueue.main.async {
                            self.logger.log("DEBUG111 send onSuccess")
                            onSuccess(actionResult)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            onError(error)
                        }
                    }
                }
                
            } catch {
                
            }
        }
    }
    
    // MARK: - Get Cloud Object
    
    public func getCloudObject(
        with options: RBSCloudObjectOptions,
        onSuccess: @escaping (RBSCloudObject) -> Void,
        onError: @escaping (RBSCloudObjectError) -> Void
    ) {
        
        guard let classId = options.classID else {
            onError(RBSCloudObjectError(error: RBSError.classIdRequired, response: nil))
            return
        }
        
        if let instance = options.instanceID,
           let object = cloudObjects.filter({ $0.classID == classId && $0.instanceID == instance }).first {
            onSuccess(object)
            return
        }
        
        let parameters: [String: Any] = options.body?.compactMapValues( { $0 }) ?? [:]
        let headers = options.headers?.compactMapValues( { $0 } ) ?? [:]
        
        if (options.useLocal ?? false) && options.instanceID != nil {
            onSuccess(RBSCloudObject(
                projectID: self.projectId,
                classID: classId,
                instanceID: options.instanceID!,
                userID: "",
                userIdentity: "",
                rbs: self,
                isLocal: true
            ))
            return
        }
        
        send(
            action: "rbs.core.request.INSTANCE",
            data: parameters,
            headers: headers,
            cloudObjectOptions: options
        ) { [weak self] (response) in
            guard let self = self else {
                return
            }
            
            guard let firstResponse = response.first as? RBSCloudObjectResponse,
                  let data = firstResponse.body,
                  let cloudResponse = try? JSONDecoder().decode(RBSCloudObjectInstanceResponse.self, from: data) else {
                      return
                  }
            
            if let respInstanceId = cloudResponse.instanceId {
                
                var userIdentity: String?
                var userId: String?
                if let data = self.keychain.getData(RBSKeychainKey.token.keyName) {
                    let json = try! JSONSerialization.jsonObject(with: data, options: [])
                    if let storedTokenData = Mapper<RBSTokenData>().map(JSONObject: json), let accessToken = storedTokenData.accessToken {
                        let jwt = try! decode(jwt: accessToken)
                        if let id = jwt.claim(name: "userId").string {
                            userId = id
                        }
                        if let identity = jwt.claim(name: "identity").string {
                            userIdentity = identity
                        }
                    }
                }
                
                if let object = self.cloudObjects.filter({ $0.classID == classId && $0.instanceID == respInstanceId }).first {
                    onSuccess(object)
                } else {
                    let object = RBSCloudObject(
                        projectID: self.projectId,
                        classID: classId,
                        instanceID: respInstanceId,
                        userID: userId ?? "",
                        userIdentity: userIdentity ?? "",
                        rbs: self
                    )
                    self.cloudObjects.append(object)
                    onSuccess(object)
                }
            }
        } onError: { (error) in
            if let error = error as? BaseErrorResponse, let cloudObjectResponse = error.cloudObjectResponse {
                onError(RBSCloudObjectError(error: .cloudObjectNotFound, response: cloudObjectResponse))
            }
        }
    }
}

// MARK: - RBSCloudObject

public class RBSCloudObject {
    public struct State {
        public let user: RBSCloudObjectState
        public let role: RBSCloudObjectState
        public let `public`: RBSCloudObjectState
        
        public func removeListeners() {
            user.listener?.remove()
            role.listener?.remove()
            `public`.listener?.remove()
        }
    }
    
    private let projectID: String
    fileprivate let classID: String
    fileprivate let instanceID: String
    private let userID: String
    private let userIdentity: String
    private weak var db: Firestore?
    private weak var rbs: RBS?
    public let state: State?
    private let isLocal: Bool
    
    init(projectID: String, classID: String, instanceID: String, userID: String, userIdentity: String, rbs: RBS?, isLocal: Bool = false) {
        self.projectID = projectID
        self.classID = classID
        self.instanceID = instanceID
        self.userID = userID
        self.userIdentity = userIdentity
        self.rbs = rbs
        self.db = rbs?.db
        self.isLocal = isLocal
        
        if !isLocal {
            state = State(
                user: RBSCloudObjectState(projectID: projectID, classID: classID, instanceID: instanceID, userID: userID, userIdentity: userIdentity, state: .user, db: db),
                role: RBSCloudObjectState(projectID: projectID, classID: classID, instanceID: instanceID, userID: userID, userIdentity: userIdentity, state: .role, db: db),
                public: RBSCloudObjectState(projectID: projectID, classID: classID, instanceID: instanceID, userID: userID, userIdentity: userIdentity, state: .public, db: db)
            )
        } else {
            state = nil
        }
    }
    
    public func call(
        with options: RBSCloudObjectOptions,
        onSuccess: @escaping (RBSCloudObjectResponse) -> Void,
        onError: @escaping (RBSCloudObjectError) -> Void
    ) {
        
        var options2 = options
        options2.classID = self.classID
        options2.instanceID = self.instanceID
        
        let parameters: [String: Any] = options.body?.compactMapValues( { $0 }) ?? [:]
        let headers = options.headers?.compactMapValues( { $0 } ) ?? [:]
        
        guard let rbs = rbs else {
            return
        }
        
        rbs.send(
            action: "rbs.core.request.CALL",
            data: parameters,
            headers: headers,
            cloudObjectOptions: options2
        ) { (response) in
            if let objectResponse = response.first as? RBSCloudObjectResponse {
                onSuccess(objectResponse)
            } else {
                let errorResponse = RBSCloudObjectResponse(statusCode: -1, headers: nil, body: response.first as? Data)
                onError(RBSCloudObjectError(error: .parsingError, response: errorResponse))
            }
        } onError: { (error) in
            if let error = error as? BaseErrorResponse, let cloudObjectResponse = error.cloudObjectResponse {
                onError(RBSCloudObjectError(error: .methodReturnedError, response: cloudObjectResponse))
            }
        }
    }
    
    public func unsubscribeStates() {
        state?.removeListeners()
    }
}

// MARK: - RBSCloudObjectState

public class RBSCloudObjectState {
    let projectID: String
    let classID: String
    let instanceID: String
    let userID: String
    let userIdentity: String
    let state: CloudObjectState
    weak var db: Firestore?
    var listener: ListenerRegistration?
    
    init(projectID: String, classID: String, instanceID: String, userID: String, userIdentity: String, state: CloudObjectState, db: Firestore?) {
        self.projectID = projectID
        self.classID = classID
        self.instanceID = instanceID
        self.state = state
        self.userID = userID
        self.userIdentity = userIdentity
        self.db = db
        
    }
    
    public func subscribe(
        onSuccess: @escaping ([String: Any]?) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        var path = "/projects/\(projectID)/classes/\(classID)/instances/\(instanceID)/"
        
        guard let database = db else {
            onError(RBSError.cloudNotConfigured)
            return
        }
        
        switch state {
        case .user:
            path.append("userState/\(userID)")
            listener = database.document(path)
                .addSnapshotListener { (snap, error) in
                    guard error == nil else {
                        onError(error!)
                        return
                    }
                    
                    onSuccess(snap?.data())
                }
        case .role:
            path.append("roleState/\(userIdentity)")
            listener = database.document(path)
                .addSnapshotListener { (snap, error) in
                    guard error == nil else {
                        onError(error!)
                        return
                    }
                    
                    onSuccess(snap?.data())
                }
        case .public:
            listener = database.document(path).addSnapshotListener { (snap, error) in
                guard error == nil else {
                    onError(error!)
                    return
                }
                
                onSuccess(snap?.data())
            }
        }
    }
    
    public func unsubscribeState() {
        listener?.remove()
    }
}

enum CloudObjectState {
    case user,
         role,
         `public`
}

// MARK: - Cloud Models

public struct RBSCloudObjectOptions {
    public var classID: String?
    public var instanceID: String?
    public var keyValue: (key: String, value: String)?
    public var method: String?
    public var headers: [String: String]?
    public var queryString: [String: String]?
    public var httpMethod: Moya.Method?
    public var body: [String: Any]?
    public var useLocal: Bool?
    
    public init(
        classID: String? = nil,
        instanceID: String? = nil,
        keyValue: (key: String, value: String)? = nil,
        method: String? = nil,
        headers: [String: String]? = nil,
        queryString: [String: String]? = nil,
        httpMethod: Moya.Method? = nil,
        body: [String: Any]? = nil,
        useLocal: Bool? = nil
    ) {
        self.classID = classID
        self.instanceID = instanceID
        self.keyValue = keyValue
        self.method = method
        self.headers = headers
        self.queryString = queryString
        self.httpMethod = httpMethod
        self.body = body
        self.useLocal = useLocal
    }
}

struct RBSCloudObjectInstanceResponse: Decodable {
    let isNewInstance: Bool?
    let methods: [RBSCloudObjectMethod]?
    let instanceId: String?
}

struct RBSCloudObjectMethod: Decodable {
    let name: String?
    let readOnly: Bool?
    let sync: Bool?
    let tag: String?
}

struct CloudOption: Decodable {
    var customToken: String?
    var projectId: String?
    var apiKey: String?
    var envs: RBSFirebaseEnv?
}

struct RBSFirebaseEnv: Decodable {
    var iosAppId: String?
    var gcmSenderId: String?
}


public struct RBSCloudObjectResponse: Codable {
    public let statusCode: Int
    public let headers: [String:String]?
    public let body: Data?
}

public struct RBSCloudObjectError: Error {
    public let error: RBSError
    public let response: RBSCloudObjectResponse?
}
