
import Alamofire
import RxSwift
import Moya
import KeychainSwift
import ObjectMapper
import JWTDecode

public enum RBSClientType {
    case user(userType:String), service(secretKey:String)
}

public struct RBSUser {
    var uid:String
    var isAnonymous:Bool
}

struct RBSTokenData : Mappable {
    
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
        uid <- map["uid"]
        accessToken <- map["accessToken"]
        refreshToken <- map["refreshToken"]
    }
}

public enum RBSClientAuthStatus {
    case signedIn(user:RBSUser), signedInAnonymously(user:RBSUser), signedOut, authenticating
}

public protocol RBSClientDelegate {
    func rbsClient(client:RBS, authStatusChanged toStatus:RBSClientAuthStatus)
}

enum RBSKeychainKey {
    case token
    
    var keyName: String {
        get {
            switch self {
            case .token: return "com.rettermobile.rbs.token"
            }
        }
    }
}

enum RBSError : Error {
    case TokenError
}

class RBSAction {
    var tokenData:RBSTokenData?
    
    var successCompletion: ((_ result:[String:Any]) -> Void)?
    var errorCompletion: ((_ error:Error) -> Void)?
    var action: String?
    var data: [String:Any]?
    
    init() {
        
    }
}



public class RBS {
    
    var clientType:RBSClientType
    
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
    
    public init(clientType:RBSClientType) {
        self.clientType = clientType
        self.disposeBag = DisposeBag()

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
                    s.saveTokenData(tokenData: tokenData)
                }
            }
            .disposed(by: disposeBag)


        
        
        
        
        
        let incomingAction = commandQueueSubject
            .asObservable()
        
        
        // At every incoming action fetch the stored token in keychain.
        let tokenData = incomingAction
            .flatMapLatest({ [weak self] action -> Observable<RBSTokenData?> in
                
                if let data = self?.keychain.getData(RBSKeychainKey.token.keyName) {
                    let json = try! JSONSerialization.jsonObject(with: data, options: [])
                    return Observable.of(Mapper<RBSTokenData>().map(JSONObject: json))
                } else {
                    return Observable.of(nil)
                }
                
            })
            .share()
        
        
        
        
        
        // STORED TOKEN
        let storedToken = tokenData
            .filter { [weak self] tokenData -> Bool in
                guard let now = self?.safeNow else { return false }
                guard let tokenData = tokenData,
                      let _ = tokenData.accessToken,
                      let refreshTokenExpiresAt = tokenData.refreshTokenExpiresAt,
                      let accessTokenExpiresAt = tokenData.accessTokenExpiresAt else { return false }
                
                if refreshTokenExpiresAt > now && accessTokenExpiresAt > now {
                    return true
                    
                }
                return false
            }
            .map { $0! }
        
        
        
        
        
        
        // REFRESH TOKEN
        let refreshTokenReq = tokenData
            .filter { [weak self] tokenData -> Bool in
                guard let now = self?.safeNow else { return false }
                guard let tokenData = tokenData,
                      let refreshTokenExpiresAt = tokenData.refreshTokenExpiresAt,
                      let accessTokenExpiresAt = tokenData.accessTokenExpiresAt else { return false }
                
                if refreshTokenExpiresAt > now && accessTokenExpiresAt < now { return true }
                return false
            }
            .map({ tokenData -> RefreshTokenRequest in
                let req = RefreshTokenRequest()
                req.refreshToken = tokenData?.refreshToken
                return req
            })
            .flatMapLatest { [weak self] req in
                self!.service.rx.request(.refreshToken(request: req)).map(GetTokenResponse.self).asObservable().materialize()
            }
        
        let refreshTokenReqResp = refreshTokenReq
            .compactMap{ $0.element }
        
        let refreshedToken = refreshTokenReqResp
            .map { (tokenResponse) -> RBSTokenData? in
                tokenResponse.tokenData
            }
            .filter { $0 != nil }
            .map { $0! }
        
        
        
        
        
        // GET A NEW ANONYM TOKEN
        let getAnonymTokenReq = tokenData
            .filter { [weak self] tokenData -> Bool in
                
                guard let now = self?.safeNow else { return false }
                
                guard let tokenData = tokenData,
                      let refreshTokenExpiresAt = tokenData.refreshTokenExpiresAt else {
                    // No token data, get anonym token
                    return true
                }
                
                if refreshTokenExpiresAt > now { return false }
                
                return true
            }
            .flatMapLatest { [weak self] tokenData in
                self!.service.rx.request(.getAnonymToken(request: GetAnonymTokenRequest())).map(GetTokenResponse.self).asObservable().materialize()
            }
            .share()
        
        let getAnonymTokenReqResp = getAnonymTokenReq
            .compactMap{ $0.element }
        
        let getAnonymTokenReqRespError = getAnonymTokenReq.compactMap { $0.error?.localizedDescription }
        
        let anonymToken = getAnonymTokenReqResp
            .map { (tokenResponse) -> RBSTokenData? in
                tokenResponse.tokenData
            }
            .filter { $0 != nil }
            .map { $0! }
        
        
        
        
        
        
        // LATEST TOKEN
        let token = Observable
            .merge([storedToken, anonymToken, refreshedToken])
            .do(onNext: { [weak self] tokenData in
                self?.saveTokenData(tokenData: tokenData)
            })
            .debug("TOKEN", trimOutput: false)
        
        
        
        // FINALLY EXECUTE THE ACTION
        let executeActionReq = Observable
            .zip(incomingAction, token)
            .debug("EXECUTE_DEBUG ZIP", trimOutput: true)
            .map({ (action, tokenData) -> RBSAction in
                action.tokenData = tokenData
                return action
            })
            .map { action -> ExecuteActionRequest in
                let req = ExecuteActionRequest()
                req.accessToken = action.tokenData!.accessToken
                req.actionName = action.action!
                req.payload = action.data
                return req
            }
            .flatMapLatest { [weak self] req in
                self!.service.rx.request(.executeAction(request: req)).catchBaseError().parseJSON().asObservable().materialize()
            }
            .debug("EXECUTE_DEBUG", trimOutput: true)
            .share()
        
        let executeActionReqResp = executeActionReq.compactMap{ $0.element }
        let executeActionReqRespError = executeActionReq.compactMap{ $0.error }
        
        Observable
            .zip(executeActionReqRespError, incomingAction)
            .observeOn(MainScheduler.instance)
            .subscribe(onNext: { (error, action) in
                if let completion = action.errorCompletion {
                    completion(error)
                }
            })
            .disposed(by: disposeBag)
        
        Observable
            .zip(executeActionReqResp, incomingAction)
            .observeOn(MainScheduler.instance)
            .debug("EXECUTE_DEBUG 2", trimOutput: true)
            .subscribe { (resp, action) in
                if let completion = action.successCompletion, let resp = resp {
                    completion(resp)
                }
            }
            .disposed(by: disposeBag)
    }
    
    private var safeNow:Date {
        get {
            return Date(timeIntervalSinceNow: 30)
        }
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
                     onSuccess: @escaping (_ result:[String:Any]) -> Void,
                     onError: @escaping (_ error:Error) -> Void) {
        
        let action = RBSAction()
        action.action = actionName
        action.data = data
        action.successCompletion = onSuccess
        action.errorCompletion = onError
        self.commandQueueSubject.onNext(action)
        
    }
}






