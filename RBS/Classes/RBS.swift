
import Alamofire
import RxSwift
import Moya
import KeychainSwift
import ObjectMapper
import JWTDecode

public enum RBSClientType {
    case user(userType:String), service(secretKey:String)
}

struct RBSUser {
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

enum RBSClientAuthStatus {
    case signedIn(user:RBSUser), signedOut
}

protocol RBSClientDelegate {
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
    
    var successCompletion: ((_ result:String) -> Void)?
    var errorCompletion: ((_ error:Error) -> Void)?
    var action: String?
    var data: [String:Any]?
    
    init() {
        
    }
}



public class RBS {
    
    var clientType:RBSClientType
    var delegate:RBSClientDelegate?
    var service:MoyaProvider<RBSService>!
    var disposeBag:DisposeBag
    let keychain = KeychainSwift()
    
    let commandQueueSubject = PublishSubject<RBSAction>()
    
    public init(clientType:RBSClientType) {
        self.clientType = clientType
        self.disposeBag = DisposeBag()
        
        self.service = MoyaProvider<RBSService>(plugins: [ CachePolicyPlugin() ])
        
        
//        let a = RBSTokenData(JSON: [
//            "isAnonym": false,
//            "uid": "123",
//            "accessToken": "123",
//            "refreshToken": "123"
//        ])
//
//        let data = try! JSONSerialization.data(withJSONObject: a?.toJSON() ?? [], options: .prettyPrinted)
//        keychain.set(data, forKey: RBSKeychainKey.token.keyName)
        
        
//        keychain.delete(RBSKeychainKey.token.keyName)
        
        let incomingAction = commandQueueSubject
            .asObservable()
        
        let tokenData = self.getTokenData()
        
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
        
        let getAnonymTokenReqResp = getAnonymTokenReq
            .compactMap{ $0.element }
            
        let getAnonymTokenReqRespError = getAnonymTokenReq.compactMap { $0.error?.localizedDescription }

        let anonymToken = getAnonymTokenReqResp
            .map { (tokenResponse) -> RBSTokenData? in
                tokenResponse.tokenData
            }
            .filter { $0 != nil }
            .map { $0! }
            
        
        
        
        
        
        
        let token = Observable
            .merge([storedToken, anonymToken, refreshedToken])
            .do(onNext: { [weak self] tokenData in
                self?.saveTokenData(tokenData: tokenData)
            })
            .debug("TOKEN", trimOutput: false)
        
        
        
        let executeActionReq = Observable
            .combineLatest(incomingAction, token)
            .map({ (action, tokenData) -> RBSAction in
                action.tokenData = tokenData
                return action
            })
            .map { action -> ExecuteActionRequest in
                let req = ExecuteActionRequest()
                req.accessToken = action.tokenData!.accessToken
                req.actionName = action.action!
                req.payload = "{'data': 1}"
                return req
            }
            .flatMapLatest { [weak self] req in
                self!.service.rx.request(.executeAction(request: req)).map(GetTokenResponse.self).asObservable().materialize()
            }
        
        let executeActionReqResp = executeActionReq.compactMap{ $0.element }
        
        Observable
            .combineLatest(executeActionReqResp, incomingAction)
            .observeOn(MainScheduler.instance)
            .subscribe { (resp, action) in
                if let completion = action.successCompletion {
                    completion("DONE")
                }
            }
            .disposed(by: disposeBag)
    }
    
    private var safeNow:Date {
        get {
            return Date(timeIntervalSinceNow: 30)
        }
    }
    
    private func saveTokenData(tokenData:RBSTokenData) {
        let obj = Mapper<RBSTokenData>().toJSON(tokenData)
        let data = try! JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted)
        self.keychain.set(data, forKey: RBSKeychainKey.token.keyName)
    }
    
    private func getAnonymToken() -> Single<GetTokenResponse> {
        return self.service.rx.request(.getAnonymToken(request: GetAnonymTokenRequest())).map(GetTokenResponse.self)
    }

    private func getTokenData() -> Observable<RBSTokenData?> {
        
        return Observable<RBSTokenData?>.create { (observer) -> Disposable in
            
            if let data = self.keychain.getData(RBSKeychainKey.token.keyName) {
                let json = try! JSONSerialization.jsonObject(with: data, options: [])
                observer.onNext(Mapper<RBSTokenData>().map(JSONObject: json))
            } else {
                observer.onNext(nil)
            }
            
            return Disposables.create()
        }
    }
    
    private func send() -> Observable<String> {
        return Observable<String>.create { (observer) -> Disposable in
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                observer.onNext("SUCCESS")
            }
            
            return Disposables.create()
        }
    }
    
    public func send(action actionName:String,
                     data:[String:Any],
                     onSuccess: @escaping (_ result:String) -> Void,
                     onError: @escaping (_ error:Error) -> Void) throws {
        
        let action = RBSAction()
        action.action = actionName
        action.data = data
        action.successCompletion = onSuccess
        action.errorCompletion = onError
        self.commandQueueSubject.onNext(action)
    }
}



