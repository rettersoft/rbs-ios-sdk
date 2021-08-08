
import Alamofire
import Moya
import KeychainSwift
import ObjectMapper
import JWTDecode
import Foundation
import TrustKit
import Starscream
import SystemConfiguration

public enum RbsRegion {
    case euWest1, euWest1Beta
    
    var getUrl:String {
        switch self {
        case .euWest1: return "https://core.rtbs.io"
        case .euWest1Beta: return "https://core-test.rettermobile.com"
        }
    }
    
    var postUrl:String {
        switch self {
        case .euWest1: return "https://core-internal.rtbs.io"
        case .euWest1Beta: return "https://core-internal-beta.rtbs.io"
        }
    }

    var socketBaseURL: URLComponents? {
        switch self {
        case .euWest1: return URLComponents(string: "wss://socket-test.rtbs.io") 
        case .euWest1Beta: return URLComponents(string: "wss://socket-test.rtbs.io")
        }
    }
}

public struct RBSConfig {
    var projectId:String?
    var secretKey:String?
    var developerId:String?
    var serviceId:String?
    var region: RbsRegion?
    
    public init(projectId:String,
                secretKey:String? = nil,
                developerId:String? = nil,
                serviceId:String? = nil,
                region:RbsRegion? = nil) {
        
        self.projectId = projectId
        self.secretKey = secretKey
        self.developerId = developerId
        self.serviceId = serviceId
        self.region = region == nil ? .euWest1 : region
    }
}

public struct RBSUser {
    public var uid:String
    public var isAnonymous:Bool
}

struct RBSTokenData : Mappable, Decodable {
    
    var projectId: String?
    var isAnonym: Bool?
    var uid: String?
    var accessToken: String?
    var refreshToken: String?
    
    
    
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
    
    
    init?(map: Map) {
        
    }
    
    mutating func mapping(map: Map) {
        isAnonym <- map["isAnonym"]
        projectId <- map["projectId"]
        uid <- map["uid"]
        accessToken <- map["accessToken"]
        refreshToken <- map["refreshToken"]
    }
}

public enum RBSClientAuthStatus {
    case signedIn(user:RBSUser),
         signedInAnonymously(user:RBSUser),
         signedOut,
         authenticating
}

public protocol RBSClientDelegate {
    func rbsClient(client:RBS, authStatusChanged toStatus:RBSClientAuthStatus)
    func socketDisconnected()
    func socketConnected()
    func socketEventFired(payload: [String: Any])
    func socketErrorOccurred(error: Error?)
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

enum RBSError : Error {
    case TokenError
}

extension String: LocalizedError {
    public var errorDescription: String? { return self }
}

class RBSAction {
    var tokenData:RBSTokenData?
    
    var successCompletion: ((_ result:[Any]) -> Void)?
    var errorCompletion: ((_ error:Error) -> Void)?
    var action: String?
    var data: [String:Any]?
    
    init() {
        
    }
}



public class RBS: WebSocketDelegate {
    
    var projectId:String!
    
    let serialQueue = DispatchQueue(label: "com.queue.Serial")
    
    let semaphore = DispatchSemaphore(value: 0)
    
    var socket: WebSocket?
    var isSocketConnected = false
    var nonSocketChangeHappened = false // to follow changes that not related to socket. ex.: background, businessAuth
    let socketSemaphore = DispatchSemaphore(value: 0)
    

    public var delegate:RBSClientDelegate? {
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
                        
                        // initiate the socket if user exists
                        self.send(action: "CONNECTSOCKET",
                                  data: [:],
                                  headers: [:]) { _ in
                            
                        } onError: { _ in
                            
                        }

                        
                    } else {
                        self.delegate?.rbsClient(client: self, authStatusChanged: .signedOut)
                        self.disconnectFromSocket()
                    }
                } else {
                    self.delegate?.rbsClient(client: self, authStatusChanged: .signedOut)
                    self.disconnectFromSocket()
                }
            } else {
                self.delegate?.rbsClient(client: self, authStatusChanged: .signedOut)
                self.disconnectFromSocket()
            }
            
        }
    }
    
    var _service:MoyaProvider<RBSService>?
    var service:MoyaProvider<RBSService>
    {
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
            self._service = MoyaProvider<RBSService>(plugins: [ CachePolicyPlugin(), accessTokenPlugin ])
            
            return self._service!
        }
    }
    
    
    let keychain = KeychainSwift()
    
    var config:RBSConfig!
    
    public init(config:RBSConfig) {
        self.setupTrustKit()
        self.config = config
        self.projectId = config.projectId
        globalRbsRegion = config.region!
        
        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(appMovedToBackground), name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appMovedToForeground), name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)
        
        
        do {
            try Network.reachability = Reachability(hostname: "www.google.com")
        }
        catch {
            switch error as? Network.Error {
            case let .failedToCreateWith(hostname)?:
                print("XXXNetwork error:\nFailed to create reachability object With host named:", hostname)
            case let .failedToInitializeWith(address)?:
                print("XXXNetwork error:\nFailed to initialize reachability object With address:", address)
            case .failedToSetCallout?:
                print("XXXNetwork error:\nFailed to set callout")
            case .failedToSetDispatchQueue?:
                print("XXXNetwork error:\nFailed to set DispatchQueue")
            case .none:
                print(error)
            }
        }
        
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(statusManager),
                                               name: .flagsChanged,
                                               object: nil)
    }
    
    @objc func statusManager(_ notification: Notification) {
        // for test purposes, delegate is used
        switch Network.reachability.status {
        case .unreachable:
            delegate?.socketEventFired(payload: ["text": "Unreachable"])
            nonSocketChangeHappened = true
            isSocketConnected = false
        case .wwan:
            if !isSocketConnected {
                delegate?.socketEventFired(payload: ["text": "Reconnecting"])
                reconnectSocket()
            }
        case .wifi:
            if !isSocketConnected {
                delegate?.socketEventFired(payload: ["text": "Reconnecting"])
                reconnectSocket()
            }
        }
    }
    
    @objc func appMovedToBackground() {
        // disconnect socket while entering background
        print("Going!!!")
        nonSocketChangeHappened = true
        disconnectFromSocket()
    }
    
    @objc func appMovedToForeground() {
        // reconnect socket while entering foreground
        print("Coming!!")
        reconnectSocket()
    }
    
    private func connectToSocket(withToken token: String?) {
        if token == nil { // is it possible?
            return
        }
        print("---connecting with token: ", token)
            
        var components = self.config.region?.socketBaseURL
        components?.queryItems = [URLQueryItem(name: "auth", value: token)]
        
        guard let url = components?.url else { return }
        
        // check if the socket is already connected
        if isSocketConnected {
            // if url is same with the old one, no need to connect again
            if let exURL = socket?.request.url, exURL == url {
                return
            } else {
                nonSocketChangeHappened = true
                socket?.disconnect()
            }
        }
        
        print("---socketURL: ", url)
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        socket = WebSocket(request: request)
        
        socket?.delegate = self
        socket?.connect()
        _ = self.socketSemaphore.wait(timeout: .distantFuture)
    }
    
    private func disconnectFromSocket() {
        socket?.disconnect()
    }
    
    public func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected(let headers):
            isSocketConnected = true
            nonSocketChangeHappened = false
            socketSemaphore.signal()
            delegate?.socketConnected()
            print("websocket is connected: \(headers)")
        case .disconnected(let reason, let code):
            isSocketConnected = false
            delegate?.socketDisconnected()
            print("websocket is disconnected: \(reason) with code: \(code)")
            if !nonSocketChangeHappened { // if a non-socket change happened, reconnect to the connect
                reconnectSocket()
            }
        case .text(let string):
            print("Received text: \(string)")
            delegate?.socketEventFired(payload: ["text": string])
        case .binary(let data):
            delegate?.socketEventFired(payload: ["data": data])
            print("Received data: \(data.count)")
        case .ping(_):
            print("---ping")
            break
        case .pong(_):
            print("---pong")
            break
        case .viabilityChanged(_):
            break
        case .reconnectSuggested(let isTrue):
            isSocketConnected = false
            if isTrue {
                reconnectSocket()
            }
        case .cancelled:
            isSocketConnected = false
            delegate?.socketDisconnected()
            if !nonSocketChangeHappened { // if a non-socket change happened, reconnect to the connect
                reconnectSocket()
            }
        case .error(let error): // TODO: we should handle this case
            print("---", error, error.debugDescription, error?.localizedDescription)
            isSocketConnected = false
            socketSemaphore.signal()
            delegate?.socketErrorOccurred(error: error)
        }
    }
    
//    public func sendSocketMessage(text: String,
//                                  completionHandler: @escaping (_ isSuccessful: Bool) -> Void) {
//        if isSocketConnected {
//            do {
//                let tokenData = try getTokenData()
//                let params = ["action": "rbs.core.request.SEND_TO_SOCKET",
//                              "userId": "\(tokenData.uid ?? "")",
//                              "message": text]
//                let encoder = JSONEncoder()
//                if let jsonData = try? encoder.encode(params) {
//                    if let jsonString = String(data: jsonData, encoding: .utf8) {
//                        socket?.write(string: jsonString) {
//                            completionHandler(true)
//                        }
//                    } else { completionHandler(false) }
//                } else { completionHandler(false) }
//            } catch {
//                print("An error occured while getting token data: \(error.localizedDescription)")
//                completionHandler(false)
//            }
//
//        } else { completionHandler(false) }
//    }
    
    private func reconnectSocket() {
        // if no token exists, no need to reconnect to the socket - signOut case
        if let _ = self.keychain.getData(RBSKeychainKey.token.keyName) {
            self.send(action: "CONNECTSOCKET",
                      data: [:],
                      headers: [:]) { _ in
                
            } onError: { _ in
                
            }
        }
    }
    
    private var safeNow:Date {
        get {
            return Date(timeIntervalSinceNow: 30)
        }
    }
    
    func setupTrustKit() {
        let pinningConfig:[String:Any] = [
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
            kTSKSwizzleNetworkDelegates: true,
            kTSKPinnedDomains: [
                "core.rtbs.io": pinningConfig,
                "core-test.rettermobile.com": pinningConfig,
                "core-internal.rtbs.io": pinningConfig,
                "core-internal-beta.rtbs.io": pinningConfig

            ]
        ] as [String : Any]
        TrustKit.initSharedInstance(withConfiguration:trustKitConfig)
    }
    
    private func getTokenData() throws -> RBSTokenData {
        
        print("getTokenData called")
        
        // Skip service tokens for now
        //        if let secretKey = self.config.secretKey, let serviceId = self.config.serviceId {
        //
        //        }
        
        let now = self.safeNow
        
        if let data = self.keychain.getData(RBSKeychainKey.token.keyName) {
            
            let json = try! JSONSerialization.jsonObject(with: data, options: [])
            
            if let tokenData = Mapper<RBSTokenData>().map(JSONObject: json),
               let refreshToken = tokenData.refreshToken,
               let refreshTokenExpiresAt = tokenData.refreshTokenExpiresAt,
               let accessTokenExpiresAt = tokenData.accessTokenExpiresAt,
               let projectId = tokenData.projectId {
                
                if(projectId == self.projectId) {
                    print("refreshTokenExpiresAt \(refreshTokenExpiresAt)")
                    print("accessTokenExpiresAt \(accessTokenExpiresAt)")
                    if refreshTokenExpiresAt > now && accessTokenExpiresAt > now {
                        // Token can be used
                        print("returning tokenData")
                        return tokenData
                    }
                    
                    if refreshTokenExpiresAt > now && accessTokenExpiresAt < now {
                        
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
    
    private func saveTokenData(tokenData:RBSTokenData?) {
        print("saveTokenData called")
        var storedUserId:String? = nil
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
                self.delegate?.rbsClient(client: self, authStatusChanged: .signedOut)
            }
            
            self.keychain.delete(RBSKeychainKey.token.keyName)
            self.disconnectFromSocket()
            
            return
        }
        
        let obj = Mapper<RBSTokenData>().toJSON(tokenData)
        let data = try! JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted)
        self.keychain.set(data, forKey: RBSKeychainKey.token.keyName)
        
        if let accessToken = tokenData.accessToken {
            let jwt = try! decode(jwt: accessToken)
            if let userId = jwt.claim(name: "userId").string, let anonymous = jwt.claim(name: "anonymous").rawValue as? Bool {
                
                if userId != storedUserId {
                    // User has changed.
                    let user = RBSUser(uid: userId, isAnonymous: anonymous)
                    
                    if anonymous {
                        DispatchQueue.main.async {
                            self.delegate?.rbsClient(client: self, authStatusChanged: .signedInAnonymously(user: user))
                        }
                        
                    } else {
                        DispatchQueue.main.async {
                            self.delegate?.rbsClient(client: self, authStatusChanged: .signedIn(user: user))
                        }
                    }
                } else {
                    
                }
                
            }
        }
    }
    
    
    private func getAnonymToken() throws -> RBSTokenData {
        print("getAnonymToken called")
        let getAnonymTokenRequest = GetAnonymTokenRequest()
        getAnonymTokenRequest.projectId = self.config.projectId
        var retVal:RBSTokenData? = nil
        
        self.service.request(.getAnonymToken(request: getAnonymTokenRequest)) {
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
        retVal?.projectId = self.config.projectId
        retVal?.isAnonym = true
        if let r = retVal {
            return r
        }
        throw "Can't get anonym token"
    }
    
    private func refreshToken(tokenData:RBSTokenData) throws -> RBSTokenData {
        print("refreshToken called")
        let refreshTokenRequest = RefreshTokenRequest()
        refreshTokenRequest.refreshToken = tokenData.refreshToken
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
    
    private func executeAction(tokenData:RBSTokenData, action:String, data:[String:Any], headers:[String:String]?) throws -> [Any] {
        print("executeAction called")
        let req = ExecuteActionRequest()
        req.projectId = self.projectId
        req.accessToken = tokenData.accessToken
        req.actionName = action
        req.payload = data
        req.headers = headers
        var errorResponse:BaseErrorResponse?
        var retVal:[Any]? = nil
        let semaphoreLocal = DispatchSemaphore(value: 0)
        self.service.request(.executeAction(request: req)) { result in
            switch result {
            case .success(let response):
                
                if (200...299).contains(response.statusCode) {
                    if let json = try! JSONSerialization.jsonObject(with: response.data, options: []) as? [Any] {
                        retVal = json
                    }
                } else {
                    errorResponse = try! response.map(BaseErrorResponse.self)
                    errorResponse!.httpStatusCode = response.statusCode
                }
                break
            case .failure(let f):
                print(f)
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
    
    
    
    // MARK: Public methods
    
    public func authenticateWithCustomToken(_ customToken:String) {
        
        print("authenticateWithCustomToken called")
        DispatchQueue.global().async {
            
            
            //        serialQueue.async {
            self.saveTokenData(tokenData: nil)
            let req = AuthWithCustomTokenRequest()
            req.customToken = customToken
            
            self.service.request(.authWithCustomToken(request: req)) {
                [weak self] result in
                
                switch result {
                case .success(let response):
                    var tokenData = try! response.map(RBSTokenData.self)
                    tokenData.projectId = self?.config.projectId
                    tokenData.isAnonym = false
                    self?.saveTokenData(tokenData: tokenData)
                    break
                default:
                    break
                }
                self?.semaphore.signal()
            }
            _ = self.semaphore.wait(wallTimeout: .distantFuture)
        }
        
        
    }
    
    public func signOut() {
        self.saveTokenData(tokenData: nil)
    }
    
    
    public func generateGetActionUrl(action actionName:String,
                                     data:[String:Any],
                                     onSuccess: @escaping (_ result:String) -> Void,
                                     onError: @escaping (_ error:Error) -> Void) {
        serialQueue.async {
            do {
                
                let tokenData = try self.getTokenData()
                self.saveTokenData(tokenData: tokenData)
                
                let req = ExecuteActionRequest()
                req.projectId = self.projectId
                req.accessToken = tokenData.accessToken
                req.actionName = actionName
                req.payload = data
                
                let s:RBSService = .executeAction(request: req)
                
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
    
    public func send(action actionName:String,
                     data:[String:Any],
                     headers:[String:String]?,
                     onSuccess: @escaping (_ result:[Any]) -> Void,
                     onError: @escaping (_ error:Error) -> Void) {
        
        print("send called")
        
        serialQueue.async {
            
            
            print("send called in async block")
            
            do {
                
                let tokenData = try self.getTokenData()
                
                self.saveTokenData(tokenData: tokenData)
                self.connectToSocket(withToken: tokenData.accessToken)
                
                if actionName == "CONNECTSOCKET" {
                    return
                }
                DispatchQueue.global().async {
                    do {
                        let actionResult = try self.executeAction(tokenData: tokenData, action: actionName, data: data, headers: headers)
                        
                        DispatchQueue.main.async {
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
}

struct Connectivity {
  static let sharedInstance = NetworkReachabilityManager()!
  static var isConnectedToInternet:Bool {
      return self.sharedInstance.isReachable
    }
}

class Reachability {
    var hostname: String?
    var isRunning = false
    var isReachableOnWWAN: Bool
    var reachability: SCNetworkReachability?
    var reachabilityFlags = SCNetworkReachabilityFlags()
    let reachabilitySerialQueue = DispatchQueue(label: "ReachabilityQueue")
    init?(hostname: String) throws {
        guard let reachability = SCNetworkReachabilityCreateWithName(nil, hostname) else {
            throw Network.Error.failedToCreateWith(hostname)
        }
        self.reachability = reachability
        self.hostname = hostname
        isReachableOnWWAN = true
        try start()
    }
    init() throws {
        var zeroAddress = sockaddr_in()
        zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        zeroAddress.sin_family = sa_family_t(AF_INET)
        guard let reachability = withUnsafePointer(to: &zeroAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else {
            throw Network.Error.failedToInitializeWith(zeroAddress)
        }
        
        self.reachability = reachability
        isReachableOnWWAN = true
        
        try start()
    }
    
    var status: Network.Status {
        return  !isConnectedToNetwork ? .unreachable :
                isReachableViaWiFi    ? .wifi :
                isRunningOnDevice     ? .wwan : .unreachable
    }
    
    var isRunningOnDevice: Bool = {
        #if targetEnvironment(simulator)
            return false
        #else
            return true
        #endif
    }()
    deinit { stop() }
}

//***

extension Reachability {
    
    func start() throws {
        guard let reachability = reachability, !isRunning else { return }
        var context = SCNetworkReachabilityContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        context.info = Unmanaged<Reachability>.passUnretained(self).toOpaque()
        guard SCNetworkReachabilitySetCallback(reachability, callout, &context) else { stop()
            throw Network.Error.failedToSetCallout
        }
        guard SCNetworkReachabilitySetDispatchQueue(reachability, reachabilitySerialQueue) else { stop()
            throw Network.Error.failedToSetDispatchQueue
        }
        reachabilitySerialQueue.async { self.flagsChanged() }
        isRunning = true
    }
    
    func stop() {
        defer { isRunning = false }
        guard let reachability = reachability else { return }
        SCNetworkReachabilitySetCallback(reachability, nil, nil)
        SCNetworkReachabilitySetDispatchQueue(reachability, nil)
        self.reachability = nil
    }
    
    var isConnectedToNetwork: Bool {
        return isReachable &&
               !isConnectionRequiredAndTransientConnection &&
               !(isRunningOnDevice && isWWAN && !isReachableOnWWAN)
    }
    
    var isReachableViaWiFi: Bool {
        return isReachable && isRunningOnDevice && !isWWAN
    }

    /// Flags that indicate the reachability of a network node name or address, including whether a connection is required, and whether some user intervention might be required when establishing a connection.
    var flags: SCNetworkReachabilityFlags? {
        guard let reachability = reachability else { return nil }
        var flags = SCNetworkReachabilityFlags()
        return withUnsafeMutablePointer(to: &flags) {
            SCNetworkReachabilityGetFlags(reachability, UnsafeMutablePointer($0))
            } ? flags : nil
    }
    
    /// compares the current flags with the previous flags and if changed posts a flagsChanged notification
    func flagsChanged() {
        guard let flags = flags, flags != reachabilityFlags else { return }
        reachabilityFlags = flags
        NotificationCenter.default.post(name: .flagsChanged, object: self)
    }
    
    /// The specified node name or address can be reached via a transient connection, such as PPP.
    var transientConnection: Bool { return flags?.contains(.transientConnection) == true }
    
    /// The specified node name or address can be reached using the current network configuration.
    var isReachable: Bool { return flags?.contains(.reachable) == true }
    
    /// The specified node name or address can be reached using the current network configuration, but a connection must first be established. If this flag is set, the kSCNetworkReachabilityFlagsConnectionOnTraffic flag, kSCNetworkReachabilityFlagsConnectionOnDemand flag, or kSCNetworkReachabilityFlagsIsWWAN flag is also typically set to indicate the type of connection required. If the user must manually make the connection, the kSCNetworkReachabilityFlagsInterventionRequired flag is also set.
    var connectionRequired: Bool { return flags?.contains(.connectionRequired) == true }
    
    /// The specified node name or address can be reached using the current network configuration, but a connection must first be established. Any traffic directed to the specified name or address will initiate the connection.
    var connectionOnTraffic: Bool { return flags?.contains(.connectionOnTraffic) == true }
    
    /// The specified node name or address can be reached using the current network configuration, but a connection must first be established.
    var interventionRequired: Bool { return flags?.contains(.interventionRequired) == true }
    
    /// The specified node name or address can be reached using the current network configuration, but a connection must first be established. The connection will be established "On Demand" by the CFSocketStream programming interface (see CFStream Socket Additions for information on this). Other functions will not establish the connection.
    var connectionOnDemand: Bool { return flags?.contains(.connectionOnDemand) == true }
    
    /// The specified node name or address is one that is associated with a network interface on the current system.
    var isLocalAddress: Bool { return flags?.contains(.isLocalAddress) == true }
    
    /// Network traffic to the specified node name or address will not go through a gateway, but is routed directly to one of the interfaces in the system.
    var isDirect: Bool { return flags?.contains(.isDirect) == true }
    
    /// The specified node name or address can be reached via a cellular connection, such as EDGE or GPRS.
    var isWWAN: Bool { return flags?.contains(.isWWAN) == true }
    
    /// The specified node name or address can be reached using the current network configuration, but a connection must first be established. If this flag is set
    /// The specified node name or address can be reached via a transient connection, such as PPP.
    var isConnectionRequiredAndTransientConnection: Bool {
        return (flags?.intersection([.connectionRequired, .transientConnection]) == [.connectionRequired, .transientConnection]) == true
    }
}

//***

func callout(reachability: SCNetworkReachability, flags: SCNetworkReachabilityFlags, info: UnsafeMutableRawPointer?) {
    guard let info = info else { return }
    DispatchQueue.main.async {
        Unmanaged<Reachability>
            .fromOpaque(info)
            .takeUnretainedValue()
            .flagsChanged()
    }
}

//***

extension Notification.Name {
    static let flagsChanged = Notification.Name("FlagsChanged")
}

//***

struct Network {
    static var reachability: Reachability!
    enum Status: String {
        case unreachable, wwan, wifi
      
    }
    enum Error: Swift.Error {
        case failedToSetCallout
        case failedToSetDispatchQueue
        case failedToCreateWith(String)
        case failedToInitializeWith(sockaddr_in)
    }
}
