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

import XCTest
@testable import BMSCore

class BaseRequestTests: XCTestCase {
    
    
    // MARK: init
    
    func testInitWithAllParameters() {
        
        let request = BaseRequest(url: "http://example.com", headers:[BaseRequest.CONTENT_TYPE: "text/plain"], queryParameters: ["someKey": "someValue"], method: HttpMethod.GET, timeout: 10.0)
        
        XCTAssertEqual(request.resourceUrl, "http://example.com")
        XCTAssertEqual(request.httpMethod.rawValue, "GET")
        XCTAssertEqual(request.timeout, 10.0)
        XCTAssertEqual(request.headers, [BaseRequest.CONTENT_TYPE: "text/plain"])
        XCTAssertEqual(request.queryParameters!, ["someKey": "someValue"])
        XCTAssertNotNil(request.networkRequest)
    }
    
    func testInitWithRelativeUrl() {
    
        #if swift(>=3.0)
            BMSClient.sharedInstance.initializeWithBluemixAppRoute(bluemixAppRoute: "https://mybluemixapp.net", bluemixAppGUID: "1234", bluemixRegion: BMSClient.REGION_US_SOUTH)
        #else
            BMSClient.sharedInstance.initialize(bluemixAppRoute: "https://mybluemixapp.net", bluemixAppGUID: "1234", bluemixRegion: BMSClient.REGION_US_SOUTH)
        #endif
        
        let request = BaseRequest(url: "/path/to/resource", headers: nil, queryParameters: nil)
        
        XCTAssertEqual(request.resourceUrl, "https://mybluemixapp.net/path/to/resource")
    }
    
    func testInitWithDefaultParameters() {
        
        let request = BaseRequest(url: "http://example.com", headers: nil, queryParameters: nil)
        
        XCTAssertEqual(request.resourceUrl, "http://example.com")
        XCTAssertEqual(request.httpMethod.rawValue, "GET")
        XCTAssertEqual(request.timeout, BMSClient.sharedInstance.defaultRequestTimeout)
        XCTAssertTrue(request.headers.isEmpty)
        XCTAssertTrue(request.headers.isEmpty)
        XCTAssertNotNil(request.networkRequest)
    }
    
    
    
    // MARK: send
    
    func testSendData() {
        
        let request = BaseRequest(url: "http://example.com", headers: nil, queryParameters: ["someKey": "someValue"])
        
        #if swift(>=3.0)
            let requestData = "{\"key1\": \"value1\", \"key2\": \"value2\"}".data(using: .utf8)
            request.sendData(requestBody: requestData!, completionHandler: nil)
        #else
            let requestData = "{\"key1\": \"value1\", \"key2\": \"value2\"}".dataUsingEncoding(NSUTF8StringEncoding)
            request.sendData(requestData!, completionHandler: nil)
        #endif
        
        XCTAssertNotNil(request.headers["x-wl-analytics-tracking-id"])
        XCTAssertNil(request.headers["x-mfp-analytics-metadata"]) // This can only be set by the BMSAnalytics framework
        
        XCTAssertEqual(request.requestBody, requestData)
        XCTAssertEqual(request.resourceUrl, "http://example.com?someKey=someValue")
    }

    
    func testSendString() {
        
        let request = BaseRequest(url: "http://example.com", headers: nil, queryParameters: ["someKey": "someValue"])
        let dataString = "Some data text"
        
        #if swift(>=3.0)
            request.sendString(requestBody: dataString, completionHandler: nil)
            let requestBodyAsString = String(data: request.requestBody!, encoding: .utf8)
        #else
            request.sendString(dataString, completionHandler: nil)
            let requestBodyAsString = NSString(data: request.requestBody!, encoding: NSUTF8StringEncoding) as? String
        #endif
        
        XCTAssertNotNil(request.headers["x-wl-analytics-tracking-id"])
        XCTAssertNil(request.headers["x-mfp-analytics-metadata"]) // This can only be set by the BMSAnalytics framework
        
        XCTAssertEqual(requestBodyAsString, dataString)
        XCTAssertEqual(request.headers[BaseRequest.CONTENT_TYPE], "text/plain")
        XCTAssertEqual(request.resourceUrl, "http://example.com?someKey=someValue")
    }
    
    func testSendStringWithoutOverwritingContentTypeHeader() {
        
        let request = BaseRequest(url: "http://example.com", headers: [BaseRequest.CONTENT_TYPE: "media-type"], queryParameters: ["someKey": "someValue"])
        let dataString = "Some data text"
        
        #if swift(>=3.0)
            request.sendString(requestBody: dataString, completionHandler: nil)
            let requestBodyAsString = String(data: request.requestBody!, encoding: .utf8)
        #else
            request.sendString(dataString, completionHandler: nil)
            let requestBodyAsString = NSString(data: request.requestBody!, encoding: NSUTF8StringEncoding) as? String
        #endif
        
        XCTAssertNotNil(request.headers["x-wl-analytics-tracking-id"])
        XCTAssertNil(request.headers["x-mfp-analytics-metadata"]) // This can only be set by the BMSAnalytics framework
        
        XCTAssertEqual(requestBodyAsString, dataString)
        XCTAssertEqual(request.headers[BaseRequest.CONTENT_TYPE], "media-type")
        XCTAssertEqual(request.resourceUrl, "http://example.com?someKey=someValue")
    }
    
    func testSendWithMalformedUrl() {
        
        #if swift(>=3.0)
            let responseReceivedExpectation = self.expectation(description: "Receive network response")
        #else
            let responseReceivedExpectation = self.expectationWithDescription("Receive network response")
        #endif
        
        let badUrl = "!@#$%^&*()"
        let request = BaseRequest(url: badUrl, headers: nil, queryParameters: nil)
        
        #if swift(>=3.0)
            
            request.send { (response: Response?, error: NSError?) -> Void in
                XCTAssertNil(response)
                XCTAssertEqual(error?.domain, BMSCoreError.domain)
                XCTAssertEqual(error?.code, BMSCoreError.MalformedUrl.rawValue)
                
                responseReceivedExpectation.fulfill()
            }
            
            self.waitForExpectations(timeout: 5.0) { (error: Error?) -> Void in
                if error != nil {
                    XCTFail("Expectation failed with error: \(error)")
                }
            }
            
        #else
            
            request.sendWithCompletionHandler { (response: Response?, error: NSError?) -> Void in
                XCTAssertNil(response)
                XCTAssertEqual(error?.domain, BMSCoreError.domain)
                XCTAssertEqual(error?.code, BMSCoreError.MalformedUrl.rawValue)
                
                responseReceivedExpectation.fulfill()
            }
            
            self.waitForExpectationsWithTimeout(5.0) { (error: NSError?) -> Void in
                if error != nil {
                    XCTFail("Expectation failed with error: \(error)")
                }
            }
            
        #endif
    }
    
    
    
    // MARK: appendQueryParameters
    
    func testAppendQueryParametersWithEmptyParameters() {
        
        let parameters: [String: String] = [:]
        
        #if swift(>=3.0)
            let url = URL(string: "http://example.com")
            let finalUrl = String( BaseRequest.append(queryParameters: parameters, toURL: url!)! )
        #else
            let url = NSURL(string: "http://example.com")
            let finalUrl = String( BaseRequest.appendQueryParameters(parameters, toURL: url!)! )
        #endif
        
        XCTAssertEqual(finalUrl, "http://example.com")
    }
    
    
    func testAppendQueryParametersWithValidParameters() {
        
        let parameters = ["key1": "value1", "key2": "value2"]
        
        #if swift(>=3.0)
            let url = URL(string: "http://example.com")
            let finalUrl = String( BaseRequest.append(queryParameters: parameters, toURL: url!)! )
            
            XCTAssertEqual(finalUrl, "http://example.com?key2=value2&key1=value1")
        #else
            let url = NSURL(string: "http://example.com")
            let finalUrl = String( BaseRequest.appendQueryParameters(parameters, toURL: url!)! )
            
            XCTAssertEqual(finalUrl, "http://example.com?key1=value1&key2=value2")
        #endif
    }
    
    func testAppendQueryParametersWithReservedCharacters() {
        
        let parameters = ["Reserved_characters": "\"#%<>[\\]^`{|}"]
        
        #if swift(>=3.0)
            let url = URL(string: "http://example.com")
            let finalUrl = String( BaseRequest.append(queryParameters: parameters, toURL: url!)! )
            
            XCTAssert(finalUrl.contains("%22%23%25%3C%3E%5B%5C%5D%5E%60%7B%7C%7D"))
        #else
            let url = NSURL(string: "http://example.com")
            let finalUrl = String( BaseRequest.appendQueryParameters(parameters, toURL: url!)! )
            
            XCTAssert(finalUrl.containsString("%22%23%25%3C%3E%5B%5C%5D%5E%60%7B%7C%7D"))
        #endif
    }
    
    func testAppendQueryParametersDoesNotOverwriteUrlParameters() {
        
        let parameters = ["key1": "value1", "key2": "value2"]
        
        #if swift(>=3.0)
            let url = URL(string: "http://example.com?hardCodedKey=hardCodedValue")
            let finalUrl = String( BaseRequest.append(queryParameters: parameters, toURL: url!)! )
            
            XCTAssertEqual(finalUrl, "http://example.com?hardCodedKey=hardCodedValue&key2=value2&key1=value1")
        #else
            let url = NSURL(string: "http://example.com?hardCodedKey=hardCodedValue")
            let finalUrl = String( BaseRequest.appendQueryParameters(parameters, toURL: url!)! )
            
            XCTAssertEqual(finalUrl, "http://example.com?hardCodedKey=hardCodedValue&key1=value1&key2=value2")
        #endif
    }
    
    func testAppendQueryParametersWithCorrectNumberOfAmpersands() {
        
        let parameters = ["k1": "v1", "k2": "v2", "k3": "v3", "k4": "v4"]
        
        #if swift(>=3.0)
            let url = URL(string: "http://example.com")
            let finalUrl = String( BaseRequest.append(queryParameters: parameters, toURL: url!)! )
            
            let numberOfAmpersands = finalUrl.components(separatedBy: "&")
        #else
            let url = NSURL(string: "http://example.com")
            let finalUrl = String( BaseRequest.appendQueryParameters(parameters, toURL: url!)! )
            
            let numberOfAmpersands = finalUrl.componentsSeparatedByString("&")
        #endif
        
        XCTAssertEqual(numberOfAmpersands.count - 1, 3)
    }

}
