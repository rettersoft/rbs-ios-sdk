
import Alamofire
import RxSwift
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

struct RBSTokenData : Mappable {
    
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
    
    var disposeBag:DisposeBag
    let keychain = KeychainSwift()
    
    let commandQueueSubject = PublishSubject<RBSAction>()
    let authWithCustomTokenQueueSubject = PublishSubject<AuthWithCustomTokenRequest>()
    
    var config:RBSConfig!
    
    public init(config:RBSConfig) {
        
        self.disposeBag = DisposeBag()
        self.config = config
        self.projectId = config.projectId
        if let url = config.rbsUrl {
            rbsUrl = url
        }
        
        
        let authWithCustomTokenReq = authWithCustomTokenQueueSubject
            .asObservable()
            .do(onNext: { [weak self] _ in
                if let s = self {
                    s.delegate?.rbsClient(client: s, authStatusChanged: .authenticating)
                }
            })
            .flatMapLatest { [weak self] req in
                self!.service.rx.request(.authWithCustomToken(request: req)).map(GetTokenResponse.self).asObservable().materialize()
            }
        
        
        
        let authWithCustomTokenReqResp = authWithCustomTokenReq
            .compactMap{ $0.element }
        
        
        authWithCustomTokenReqResp
            .observeOn(MainScheduler.instance)
            .subscribe { [weak self] resp in
                if let s = self, let resp = resp.element, let tokenData = resp.tokenData {
                    
                    var td = RBSTokenData.init(JSON: tokenData.toJSON())
                    td?.projectId = s.projectId
                    s.saveTokenData(tokenData: td)
                }
            }
            .disposed(by: disposeBag)
        
        
        
        
        
        
        
        let incomingAction = commandQueueSubject
            .asObservable()
        
        // At every incoming action fetch the stored token in keychain.
        let tokenData = incomingAction
            .concatMap({ [weak self] action in
                return self!.getTokenData()
            })
            .do(onNext: { [weak self] tokenData in
                var td = RBSTokenData.init(JSON: tokenData.toJSON())
                td?.projectId = self?.projectId
                self!.saveTokenData(tokenData: td)
            })
        
        
        
        
        let actionResult = Observable
            .zip(incomingAction, tokenData)
            .concatMap { [weak self] (action, tokenData) -> Observable<[Any]?> in
                let req = ExecuteActionRequest()
                req.accessToken = tokenData.accessToken
                req.actionName = action.action
                req.payload = action.data
                return self!.service.rx.request(.executeAction(request: req)).parseJSON().asObservable() }
        
        
        Observable
            .zip(incomingAction, actionResult)
            .subscribe { (action, response) in
                if let completion = action.successCompletion, let result = response {
                    completion(result)
                }
            }
            .disposed(by: disposeBag)
        
    }
    
    private var safeNow:Date {
        get {
            return Date(timeIntervalSinceNow: 30)
        }
    }
    
    private func getTokenData() -> Observable<RBSTokenData> {
        
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
                    if refreshTokenExpiresAt > now && accessTokenExpiresAt > now {
                        // Token can be used
                        return Observable.just(tokenData)
                    }
                    
                    if refreshTokenExpiresAt > now && accessTokenExpiresAt < now {
                        
                        // DO REFRESH
                        let refreshTokenRequest = RefreshTokenRequest()
                        refreshTokenRequest.refreshToken = refreshToken
                        return self.service.rx.request(.refreshToken(request: refreshTokenRequest)).map(GetTokenResponse.self).map({ response in
                            return response.tokenData!
                        }).asObservable()
                    }
                }
                
                
                
            }
        }
        
        // Get anonym token
        let getAnonymTokenRequest = GetAnonymTokenRequest()
        getAnonymTokenRequest.projectId = self.config.projectId
        
        return self
            .service
            .rx
            .request(.getAnonymToken(request: getAnonymTokenRequest))
            .map(GetTokenResponse.self).map({ response in
                return response.tokenData!
            }).asObservable()
        
        
    }
    
    private func saveTokenData(tokenData:RBSTokenData?) {
        
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
                        self.delegate?.rbsClient(client: self, authStatusChanged: .signedInAnonymously(user: user))
                    } else {
                        self.delegate?.rbsClient(client: self, authStatusChanged: .signedIn(user: user))
                    }
                } else {
                    
                }
                
            }
        }
    }
    
    
    
    
    // MARK: Public methods
    
    public func authenticateWithCustomToken(_ customToken:String) {
        self.saveTokenData(tokenData: nil)
        let req = AuthWithCustomTokenRequest()
        req.customToken = customToken
        self.authWithCustomTokenQueueSubject.onNext(req)
    }
    
    public func signOut() {
        self.saveTokenData(tokenData: nil)
    }
    
    public func send(action actionName:String,
                     data:[String:Any],
                     onSuccess: @escaping (_ result:[Any]) -> Void,
                     onError: @escaping (_ error:Error) -> Void) {
        
        let action = RBSAction()
        action.action = actionName
        action.data = data
        action.successCompletion = onSuccess
        action.errorCompletion = onError
        self.commandQueueSubject.onNext(action)
        
    }
}






