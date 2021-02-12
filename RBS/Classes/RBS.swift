
import Alamofire
import Moya
import KeychainSwift
import ObjectMapper
import JWTDecode

public struct RBSConfig {
    var projectId:String?
    var secretKey:String?
    var developerId:String?
    var serviceId:String?
    var rbsUrl:String?
    
    public init(projectId:String, secretKey:String? = nil, developerId:String? = nil, serviceId:String? = nil, rbsUrl:String? = nil) {
        self.projectId = projectId
        self.secretKey = secretKey
        self.developerId = developerId
        self.serviceId = serviceId
        self.rbsUrl = rbsUrl
    }
}

public struct RBSUser {
    var uid:String
    var isAnonymous:Bool
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



public class RBS {
    
    var projectId:String!
    
    let serialQueue = DispatchQueue(label: "com.queue.Serial")
    
    let semaphore = DispatchSemaphore(value: 0)
    
    
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
                        
                        
                    }
                }
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
        
        self.config = config
        self.projectId = config.projectId
        if let url = config.rbsUrl {
            rbsUrl = url
        }
        
    }
    
    private var safeNow:Date {
        get {
            return Date(timeIntervalSinceNow: 30)
        }
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
    
    private func executeAction(tokenData:RBSTokenData, action:String, data:[String:Any]) throws -> [Any] {
        print("executeAction called")
        let req = ExecuteActionRequest()
        req.projectId = self.projectId
        req.accessToken = tokenData.accessToken
        req.actionName = action
        req.payload = data
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
    
    public func send(action actionName:String,
                     data:[String:Any],
                     onSuccess: @escaping (_ result:[Any]) -> Void,
                     onError: @escaping (_ error:Error) -> Void) {
        
        print("send called")
        
        serialQueue.async {

            
            print("send called in async block")
            
            do {
                
                let tokenData = try self.getTokenData()
                
                self.saveTokenData(tokenData: tokenData)
                
                DispatchQueue.global().async {
                    do {
                        let actionResult = try self.executeAction(tokenData: tokenData, action: actionName, data: data)
                        
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






