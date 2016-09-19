/*
*     Copyright 2016 IBM Corp.
*     Licensed under the Apache License, Version 2.0 (the "License");
*     you may not use this file except in compliance with the License.
*     You may obtain a copy of the License at
*     http://www.apache.org/licenses/LICENSE-2.0
*     Unless required by applicable law or agreed to in writing, software
*     distributed under the License is distributed on an "AS IS" BASIS,
*     WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
*     See the License for the specific language governing permissions and
*     limitations under the License.
*/


public class Request: BaseRequest {
    
    
    // MARK: Properties (internal)
    
    internal var oauthFailCounter = 0
    
#if swift(>=3.0)
    internal var savedRequestBody: Data?
#else
    internal var savedRequestBody: NSData?
#endif
    
    // MARK: Initializer
    
    public init(url: String, method: HttpMethod) {
        super.init(url: url, headers: nil, queryParameters:nil, method: method)
    }
    
    
    
    // MARK: Method overrides
    
    
#if swift(>=3.0)
    
    
    // This is required since the other custom Request initializer overrides this superclass initializer
    public override init(url: String,
                       headers: [String: String]?,
                       queryParameters: [String: String]?,
                       method: HttpMethod = HttpMethod.GET,
                       timeout: Double = BMSClient.sharedInstance.defaultRequestTimeout,
                       cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy) {
     
		super.init(url: url, headers: headers, queryParameters: queryParameters, method: method, timeout: timeout, cachePolicy: cachePolicy)
    }
    
    public override func send(completionHandler: BmsCompletionHandler?) {
        
        let authManager: AuthorizationManager = BMSClient.sharedInstance.authorizationManager
        
        if let authHeader: String = authManager.cachedAuthorizationHeader {
            self.headers["Authorization"] = authHeader
        }
        
        savedRequestBody = requestBody
        
        let sendCompletionHandler : BmsCompletionHandler = {(response: Response?, error: Error?) in
            
            guard error == nil else {
				if let completionHandler = completionHandler{
					completionHandler(response, error)
				}
                return
            }
			
			let authManager = BMSClient.sharedInstance.authorizationManager;
            guard let unWrappedResponse = response,
					authManager.isAuthorizationRequired(forHttpResponse: unWrappedResponse) &&
                    self.oauthFailCounter < 2
			else {
                self.oauthFailCounter += 1
                if (response?.statusCode)! >= 400 {
                    completionHandler?(response, BMSCoreError.ServerRespondedWithError)
                }
                else {
                    completionHandler?(response, nil)
                }
                return
            }
            
            self.oauthFailCounter += 1
            
            let authCallback: BmsCompletionHandler = {(response: Response?, error:Error?) in
                if error == nil {
                    if let myRequestBody = self.requestBody {
                        self.sendData(requestBody: myRequestBody, completionHandler: completionHandler)
                    }
                    else {
                        self.send(completionHandler: completionHandler)
                    }
                } else {
                    completionHandler?(response, error)
                }
            }
			authManager.obtainAuthorization(completionHandler: authCallback)
        }
        
        super.send(completionHandler: sendCompletionHandler)
    }
    
    
#else
    
    
    // This is required since the other custom Request initializer overrides this superclass initializer
    public override init(url: String,
                       headers: [String: String]?,
                       queryParameters: [String: String]?,
                       method: HttpMethod = HttpMethod.GET,
                       timeout: Double = BMSClient.sharedInstance.defaultRequestTimeout,
                       cachePolicy: NSURLRequestCachePolicy = NSURLRequestCachePolicy.UseProtocolCachePolicy) {
        
        super.init(url: url, headers: headers, queryParameters: queryParameters, method: method, timeout: timeout, cachePolicy: cachePolicy)
    }
    
    public override func sendWithCompletionHandler(callback: BmsCompletionHandler?) {
        
        let authManager: AuthorizationManager = BMSClient.sharedInstance.authorizationManager
        
        if let authHeader: String = authManager.cachedAuthorizationHeader {
            self.headers["Authorization"] = authHeader
        }
        
        savedRequestBody = requestBody
        
        let myCallback : BmsCompletionHandler = {(response: Response?, error: NSError?) in
            
            guard error == nil else {
                if let callback = callback{
                    callback(response, error)
                }
                return
            }
            
            let authManager = BMSClient.sharedInstance.authorizationManager;
            guard let unWrappedResponse = response where
                authManager.isAuthorizationRequired(forHttpResponse: unWrappedResponse) &&
                    self.oauthFailCounter < 2
                else {
                    self.oauthFailCounter += 1
                    if (response?.statusCode)! >= 400 {
                        callback?(response, NSError(domain: BMSCoreError.domain, code: BMSCoreError.ServerRespondedWithError.rawValue, userInfo: nil))
                    }
                    else {
                        callback?(response, nil)
                    }
                    return
            }
            
            self.oauthFailCounter += 1
            
            let authCallback: BmsCompletionHandler = {(response: Response?, error:NSError?) in
                if error == nil {
                    if let myRequestBody = self.requestBody {
                        self.sendData(myRequestBody, completionHandler: callback)
                    }
                    else {
                        self.sendWithCompletionHandler(callback)
                    }
                } else {
                    callback?(response, error)
                }
            }
            authManager.obtainAuthorization(completionHandler: authCallback)
        }
        
        super.sendWithCompletionHandler(myCallback)
    }
    
    
#endif
    
    
}
