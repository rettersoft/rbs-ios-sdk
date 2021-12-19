//
//  RBSService.swift
//  RBS
//
//  Created by Baran Baygan on 19.11.2020.
//


import Foundation
import Moya
import ObjectMapper


var globalRbsRegion:RbsRegion = .euWest1

let cloudObjectActions = ["rbs.core.request.INSTANCE", "rbs.core.request.CALL"]

enum RBSService {
    
    case getAnonymToken(request: GetAnonymTokenRequest)
    case executeAction(request: ExecuteActionRequest)
    
    case refreshToken(request: RefreshTokenRequest)
    case authWithCustomToken(request: AuthWithCustomTokenRequest)
    
    var endPoint: String {
        switch self {
        case .getAnonymToken(_): return "/public/anonymous-auth"
        case .executeAction(let request):

            let isExcludedAction = cloudObjectActions.contains(request.actionName ?? "")
            
            if !isExcludedAction {
                return "/user/action/\(request.projectId!)/\(request.actionName!)"
            } else {
                if request.actionName == "rbs.core.request.CALL" {
                    return "CALL/\(request.classID ?? "")/\(request.method ?? "")/\(request.instanceID ?? "")"
                }
                
                if request.actionName == "rbs.core.request.STATE" {
                    return "STATE/\(request.classID ?? "")/\(request.instanceID ?? "")"
                }
                
                if let instanceID = request.instanceID {
                    return "/INSTANCE/\(request.classID ?? "")/\(instanceID)"
                } else if let keyValue = request.keyValue {
                    return "/INSTANCE/\(request.classID ?? "")/\(keyValue.key)!\(keyValue.value)"
                } else {
                    return "/INSTANCE/\(request.classID ?? "")"
                }
                
            }
        case .refreshToken(_): return "/public/auth-refresh"
        case .authWithCustomToken(_): return "/public/auth"
        }
    }
    
    var body: [String:Any] {
        switch self {
        case .executeAction(let request):
            if let payload = request.payload {
                return payload
            }
            return [:]
        default: return [:]
        }
    }
    
    func isGetAction(_ action:String?) -> Bool {
        guard let actionName = action else { return false }
        let actionType = actionName.split(separator: ".")[2]
        return actionType == "get"
    }
    
    var urlParameters: [String: Any] {
        switch self {
        case .getAnonymToken(let request):
            return [
                "projectId": request.projectId!,
                "platform": "IOS"
            ]
        case .refreshToken(let request): return ["refreshToken":request.refreshToken!, "platform": "IOS"]
        case .authWithCustomToken(let request): return ["customToken": request.customToken!, "platform": "IOS"]
            
        case .executeAction(let request):
            
            if cloudObjectActions.contains(request.actionName ?? "") {

                var parameters: [String: Any] =  [
                    "_token": request.accessToken != nil ? request.accessToken! : "",
                ]
                
                if let queryParameters = request.queryString {
                    for (key, value) in queryParameters {
                        parameters[key] = value
                    }
                }
                return parameters
            }
            
            if let action = request.actionName {
               
                let accessToken = request.accessToken != nil ? request.accessToken! : ""
                
                if(self.isGetAction(action)) {
                    let payload: [String:Any] = request.payload == nil ? [:] : request.payload!
                    let data: Data = try! JSONSerialization.data(withJSONObject:payload, options: JSONSerialization.WritingOptions.prettyPrinted)
                    let dataBase64 = data.base64EncodedString().addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                    var parameters =  [
                        "auth": accessToken,
                        "platform": "IOS",
                        "data": dataBase64!
                    ]
                    
                    if let culture = request.culture {
                        parameters["culture"] = culture
                    }
                    
                    return parameters
                } else {
                    var parameters = ["auth": accessToken]
                    if let culture = request.culture {
                        parameters["culture"] = culture
                    }
                    
                    return parameters
                }
                
            } else {
                
                return [:]
                
            }
        }
    }
    
    var httpMethod: Moya.Method {
        switch self {
        case .executeAction(let request):

            let isExcludedAction = cloudObjectActions.contains(request.actionName ?? "")

            if !isExcludedAction {
                if(self.isGetAction(request.actionName)) {
                    return .get
                }
                
                return .post
            } else {
                return request.httpMethod ?? .post
            }
            
        default: return .get
        }
    }
}


extension RBSService: TargetType, AccessTokenAuthorizable {
    var authorizationType: AuthorizationType? {
        switch self {
        default: return .none
        }
    }
    
    var baseURL: URL {
        switch self {
        case .executeAction(let request):
            
            let isExcludedAction = cloudObjectActions.contains(request.actionName ?? "")
            
            if !isExcludedAction {
                if(self.isGetAction(request.actionName)) {
                    return URL(string: globalRbsRegion.getUrl)!
                }
                return URL(string: globalRbsRegion.postUrl)!
            } else {
                return URL(string: "https://\(request.projectId!).\(globalRbsRegion.apiURL)")!
            }
        default:
            return URL(string: globalRbsRegion.postUrl)!
        }
    }
    var path: String { return self.endPoint }
    var method: Moya.Method { return self.httpMethod }
    var sampleData: Data {
        switch self {
        default:
            return Data()
        }
    }
    var task: Task {
        switch self {
        case .executeAction(let request):
            
            if(self.isGetAction(request.actionName)) {
                return .requestParameters(parameters: self.urlParameters, encoding: URLEncoding.default)
            }
            
            return .requestCompositeParameters(bodyParameters: self.body,
                                               bodyEncoding: JSONEncoding.default,
                                               urlParameters: self.urlParameters)
        default:
            return .requestParameters(parameters: self.urlParameters, encoding: URLEncoding.default)
        }
    }
    func getLanguageISO() -> String {
        let locale = Locale.current
        guard let languageCode = locale.languageCode,
              let regionCode = locale.regionCode else {
            return "en_US"
        }
        return languageCode + "_" + regionCode
    }
    var headers: [String : String]? {
        
        var headers: [String: String] = [:]
        headers["Content-Type"] = "application/json"
        headers["x-rbs-sdk-client"] = "ios"
        
        switch self {
        case .executeAction(let request):
            if var reqHeaders = request.headers {
                if(!reqHeaders.keys.contains { $0 == "accept-language" || $0 == "Accept-Language" }) {
                    reqHeaders["accept-language"] = self.getLanguageISO()
                }
                for h in reqHeaders {
                    headers[h.key] = h.value
                }
            }
            
            headers["Content-Type"] = "application/json"
            break
        default:
            break
        }
        
        return headers
    }
}

extension RBSService : CachePolicyGettable {
    var cachePolicy: URLRequest.CachePolicy {
        get {
            .reloadIgnoringLocalAndRemoteCacheData
        }
    }
}

protocol CachePolicyGettable {
    var cachePolicy: URLRequest.CachePolicy { get }
}

final class CachePolicyPlugin: PluginType {
    public func prepare(_ request: URLRequest, target: TargetType) -> URLRequest {
        if let cachePolicyGettable = target as? CachePolicyGettable {
            var mutableRequest = request
            mutableRequest.cachePolicy = cachePolicyGettable.cachePolicy
            return mutableRequest
        }
        
        return request
    }
}

import GTMSessionFetcher

// Code to swizzle `GTMSessionFetcherService.delegateDispatcherForFetcher:` in order to fix a crash
extension GTMSessionFetcherService {
  private static var delegateDispatcherForFetcherIsSwizzled: Bool = false

  static func swizzleDelegateDispatcherForFetcher() {
    if delegateDispatcherForFetcherIsSwizzled {
      return
    }
    delegateDispatcherForFetcherIsSwizzled = true

    // `delegateDispatcherForFetcher:` is private and so we cannot use `#selector(..)`
    let originalSelector = sel_registerName("delegateDispatcherForFetcher:")
    let newSelector = #selector(new_delegateDispatcherForFetcher)
    if let originalMethod = class_getInstanceMethod(self, originalSelector),
      let newMethod = class_getInstanceMethod(self, newSelector) {
      method_setImplementation(originalMethod, method_getImplementation(newMethod))
    }
  }

  /*
   Modified code from GTMSessionFetcherService.m:
   https://github.com/google/gtm-session-fetcher/blob/c879a387e0ca4abcdff9e37eb0e826f7142342b1/Source/GTMSessionFetcherService.m#L382

   Original code returns GTMSessionFetcherSessionDelegateDispatcher but it's a private class
   so we are returning NSObject which is its superclass.
   */
  // Internal utility. Returns a fetcher's delegate if it's a dispatcher, or nil if the fetcher
  // is its own delegate (possibly via proxy) and has no dispatcher.
  @objc
  private func new_delegateDispatcherForFetcher(_ fetcher: GTMSessionFetcher?) -> NSObject? {
    if let fetcherDelegate = fetcher?.session?.delegate,
      let delegateDispatcherClass = NSClassFromString("GTMSessionFetcherSessionDelegateDispatcher"),
      fetcherDelegate.isKind(of: delegateDispatcherClass) {
      return fetcherDelegate as? NSObject
    }
    return nil
  }
}
