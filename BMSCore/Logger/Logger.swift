/*
*     Copyright 2015 IBM Corp.
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


import Foundation


public enum LogLevel: Int {
    
    case None, Analytics, Fatal, Error, Warn, Info, Debug
    
    var stringValue: String {
        get {
            switch self {
            case .None:
                return "NONE"
            case .Analytics:
                return "ANALYTICS"
            case .Fatal:
                return "FATAL"
            case .Error:
                return "ERROR"
            case .Warn:
                return "WARN"
            case .Info:
                return "INFO"
            case .Debug:
                return "DEBUG"
            }
        }
    }
}


public class Logger {
    
    
    // MARK: Class constants (private)
    
    // By default, the dateFormater will convert to the local time zone, but we want to send the date based on UTC
    // so that logs from all clients in all timezones are normalized to the same GMT timezone.
    private static let dateFormatter: NSDateFormatter = Logger.generateDateFormatter()
    
    private static func generateDateFormatter() -> NSDateFormatter {
        
        let formatter = NSDateFormatter()
        formatter.locale = NSLocale(localeIdentifier: "en_US_POSIX")
        formatter.timeZone = NSTimeZone(name: "GMT")
        formatter.dateFormat = "dd-MM-yyyy HH:mm:ss:SSS"
        
        return formatter
    }
    
    private static let logsDocumentPath: String = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0]
    
    private static let fileManager = NSFileManager.defaultManager()
    
    
    
    // MARK: Dispatch queues
    
    private static let loggerFileIOQueue: dispatch_queue_t = dispatch_queue_create("com.ibm.mobilefirstplatform.clientsdk.swift.BMSCore.Logger.loggerFileIOQueue", DISPATCH_QUEUE_SERIAL)
    
    
    private static let analyticsFileIOQueue: dispatch_queue_t = dispatch_queue_create("com.ibm.mobilefirstplatform.clientsdk.swift.BMSCore.Logger.analyticsFileIOQueue", DISPATCH_QUEUE_SERIAL)
    
    
    private static let sendLogsToServerQueue: dispatch_queue_t = dispatch_queue_create("com.ibm.mobilefirstplatform.clientsdk.swift.BMSCore.Logger.sendLogsToServerQueue", DISPATCH_QUEUE_SERIAL)
    
    
    private static let sendAnalyticsToServerQueue: dispatch_queue_t = dispatch_queue_create("com.ibm.mobilefirstplatform.clientsdk.swift.BMSCore.Logger.sendAnalyticsToServerQueue", DISPATCH_QUEUE_SERIAL)
    
    
    private static let updateLogProfileQueue: dispatch_queue_t = dispatch_queue_create("com.ibm.mobilefirstplatform.clientsdk.swift.BMSCore.Logger.updateLogProfileQueue", DISPATCH_QUEUE_SERIAL)

    
    // Custom dispatch_sync that can incorporate throwable statements
    internal func dispatch_sync(queue: dispatch_queue_t, block: () throws -> ()) throws {
        
        var error: ErrorType?
        try dispatch_sync(queue) {
            do {
                try block()
            }
            catch let caughtError {
                error = caughtError
            }
        }
        if error != nil {
            throw error!
        }
    }
    
    
    // MARK: Properties (public)
    
    public let name: String
    
    public static var logStoreEnabled: Bool = true
    
    public static var logLevelFilter: LogLevel {
        get {
            let level = NSUserDefaults.standardUserDefaults().integerForKey(TAG_LOG_LEVEL)
            if level >= LogLevel.None.rawValue && level <= LogLevel.Debug.rawValue {
                return LogLevel(rawValue: level)! // The above condition guarantees a non-nil LogLevel
            }
            else {
                return LogLevel.Debug
            }
        }
        set {
            NSUserDefaults.standardUserDefaults().setInteger(newValue.rawValue, forKey: TAG_LOG_LEVEL)
        }
    }
    
    public static var maxLogStoreSize: Int {
        get {
            return NSUserDefaults.standardUserDefaults().integerForKey(TAG_MAX_STORE_SIZE) ?? DEFAULT_MAX_STORE_SIZE
        }
        set {
            NSUserDefaults.standardUserDefaults().setInteger(newValue, forKey: TAG_MAX_STORE_SIZE)
        }
    }
    
    public static var uncaughtExceptionDetected: Bool {
        get {
            return false
        }
    }
    
    public static var internalSDKLoggingEnabled: Bool {
        get {
            return true
        }
        set {
            
        }
    }
    
    
    
    // MARK: Properties (internal/private)
    
    internal static var loggerInstances: [String: Logger] = [:]
    
    internal static let internalLogger = Logger.getLoggerForName(MFP_LOGGER_PACKAGE)
    
    
    
    // MARK: Initializers
    
    public static func getLoggerForName(loggerName: String) -> Logger {
        
        if Logger.loggerInstances.isEmpty {
            // Only need to set uncaught exception handler once, when the first Logger instance is created
            captureUncaughtExceptions()
        }
        
        if let existingLogger = Logger.loggerInstances[loggerName] {
            return existingLogger
        }
        else {
            let newLogger = Logger(name: loggerName)
            Logger.loggerInstances[loggerName] = newLogger
            
            return newLogger
        }
    }
    
    
    private init(name: String) {
        self.name = name
    }
    
    
    
    // MARK: Log methods
    // TODO: Make use of the "error" parameter or remove it
    public func debug(message: String, error: ErrorType? = nil, file: String = __FILE__, function: String = __FUNCTION__, line: Int = __LINE__) {
        
        logMessage(message, level: LogLevel.Debug, error: error, calledFile: file, calledFunction: function, calledLineNumber: line)
    }
    
    
    public func info(message: String, error: ErrorType? = nil, file: String = __FILE__, function: String = __FUNCTION__, line: Int = __LINE__) {
    
        logMessage(message, level: LogLevel.Info, error: error, calledFile: file, calledFunction: function, calledLineNumber: line)
    }
    
    
    public func warn(message: String, error: ErrorType? = nil, file: String = __FILE__, function: String = __FUNCTION__, line: Int = __LINE__) {
        
        logMessage(message, level: LogLevel.Warn, error: error, calledFile: file, calledFunction: function, calledLineNumber: line)
    }
    
    
    public func error(message: String, error: ErrorType? = nil, file: String = __FILE__, function: String = __FUNCTION__, line: Int = __LINE__) {
        
        logMessage(message, level: LogLevel.Error, error: error, calledFile: file, calledFunction: function, calledLineNumber: line)
    }
    
    
    public func fatal(message: String, error: ErrorType? = nil, file: String = __FILE__, function: String = __FUNCTION__, line: Int = __LINE__) {
        
        logMessage(message, level: LogLevel.Fatal, error: error, calledFile: file, calledFunction: function, calledLineNumber: line)
    }
    
    
    internal func analytics(metadata: [String: AnyObject], error: ErrorType? = nil, file: String = __FILE__, function: String = __FUNCTION__, line: Int = __LINE__) {
        
        logMessage("", level: LogLevel.Analytics, error: error, calledFile: file, calledFunction: function, calledLineNumber: line, additionalMetadata: metadata)
    }
    
    
    internal func logMessage(message: String, level: LogLevel, error: ErrorType?, calledFile: String, calledFunction: String, calledLineNumber: Int, additionalMetadata: [String: AnyObject]? = nil) {
        
        // TODO: dispatch_async?
        
        guard canLogAtLevel(level) else {
            return
        }
        
        if level != LogLevel.Analytics {
            // Example: [DEBUG] [mfpsdk.logger] logMessage in Logger.swift:234 :: "Some random message"
            print("[\(level.stringValue)] [\(self.name)] \(calledFunction) in \(calledFile):\(calledLineNumber) :: \(message)")
        }
        
        var logFileName: String = Logger.logsDocumentPath
        var logOverflowFileName: String = Logger.logsDocumentPath
        if level == LogLevel.Analytics {
            logFileName += FILE_LOGGER_LOGS
            logOverflowFileName += FILE_LOGGER_OVERFLOW
        }
        else {
            logFileName += FILE_ANALYTICS_LOGS
            logOverflowFileName += FILE_ANALYTICS_OVERFLOW
        }
        
        
        
        let timeStamp = Logger.dateFormatter.stringFromDate(NSDate())
    }
    
    
    internal func canLogAtLevel(level: LogLevel) -> Bool {
        
        if level == LogLevel.Analytics && Analytics.enabled == false {
            return false
        }
        if level.rawValue <= Logger.logLevelFilter.rawValue {
            return false
        }
        return true
    }
    
    
    internal func writeToFile(fileName: String, string: String) {
        
        let fileHandle = NSFileHandle(forReadingAtPath: fileName)
        let data = string.dataUsingEncoding(NSUTF8StringEncoding)
        if Logger.fileManager.isWritableFileAtPath(fileName) && fileHandle != nil && data != nil {
            fileHandle!.seekToEndOfFile()
            fileHandle?.writeData(data!)
        }
        else {
            Logger.internalLogger.warn("Cannot write to file: \(fileName).")
        }
    }
    
    
    
    // MARK: Sending logs
    
    public func send(completionHandler userCallback: MfpCompletionHandler? = nil) {
        
        let logSendCallback: MfpCompletionHandler = { (response: Response?, error: NSError?) in
            if error != nil {
                Logger.internalLogger.debug("Client logs successfully sent to the server.")
                // Remove the uncaught exception flag since the logs containing the exception(s) have just been sent to the server
                NSUserDefaults.standardUserDefaults().setBool(false, forKey: TAG_UNCAUGHT_EXCEPTION)
                self.deleteBufferFile(FILE_LOGGER_SEND)
            }
            else {
                Logger.internalLogger.error("Request to send client logs has failed.")
            }
            
            userCallback?(response, error)
        }
        
        // Use a serial queue to ensure that the same logs do not get sent more than once
        dispatch_async(Logger.sendLogsToServerQueue) { () -> Void in
            do {
                let logsToSend: String? = try self.getLogs(fileName: FILE_LOGGER_LOGS, overflowFileName: FILE_LOGGER_OVERFLOW, bufferFileName: FILE_LOGGER_SEND)
                if logsToSend != nil {
                    self.sendToServer(logsToSend!, withCallback: logSendCallback)
                }
                else {
                    Logger.internalLogger.info("There are no logs to send.")
                }
            }
            catch let error as NSError {
                logSendCallback(nil, error)
            }
        }
    }
    
    
    internal func sendAnalytics(completionHandler userCallback: MfpCompletionHandler? = nil) {
    
        // Internal completion handler - wraps around the user supplied completion handler (if supplied)
        let analyticsSendCallback: MfpCompletionHandler = { (response: Response?, error: NSError?) in
            if error != nil {
                Analytics.logger.debug("Analytics data successfully sent to the server.")
           self.deleteBufferFile(FILE_ANALYTICS_SEND)
            }
            else {
                Analytics.logger.error("Request to send analytics data to the server has failed.")
            }
            
            userCallback?(response, error)
        }
        
        // Use a serial queue to ensure that the same analytics data do not get sent more than once
        dispatch_async(Logger.sendAnalyticsToServerQueue) { () -> Void in
            do {
                let logsToSend: String? = try self.getLogs(fileName: FILE_ANALYTICS_LOGS, overflowFileName:FILE_ANALYTICS_OVERFLOW, bufferFileName: FILE_ANALYTICS_SEND)
                if logsToSend != nil {
                    self.sendToServer(logsToSend!, withCallback: analyticsSendCallback)
                }
                else {
                    Analytics.logger.info("There are no analytics data to send.")
                }
            }
            catch let error as NSError {
                analyticsSendCallback(nil, error)
            }
        }
    }
    
    
    internal func sendToServer(logs: String, withCallback callback: MfpCompletionHandler) {
        
        let bmsClient = BMSClient.sharedInstance
        
        guard var appRoute = bmsClient.bluemixAppRoute else {
            returnClientInitializationError("bluemixAppRoute", callback: callback)
            return
        }
        guard let appGuid = bmsClient.bluemixAppGUID else {
            returnClientInitializationError("bluemixAppGUID", callback: callback)
            return
        }
        
        // Build and send the Request
        
        if appRoute[appRoute.endIndex.predecessor()] != "/" {
            appRoute += "/"
        }
        let logUploadPath = "/imfmobileanalytics/v1/receiver/apps/"
        let logUploaderUrl = appRoute + logUploadPath + appGuid
        
        var headers = ["Content-Type": "application/json"]
        if let rewriteDomain = bmsClient.rewriteDomain {
            headers[REWRITE_DOMAIN_HEADER_NAME] = rewriteDomain
        }
        
        let logPayload = "[" + logs + "]"
        
        let request = Request(url: logUploaderUrl, headers: headers, queryParameters: nil, method: HttpMethod.POST)
        request.sendString(logPayload, withCompletionHandler: callback)
    }
    
    private func returnClientInitializationError(missingValue: String, callback: MfpCompletionHandler) {
        
        Logger.internalLogger.error("No value found for the BMSClient \(missingValue) property.")
        let errorMessage = "Must initialize BMSClient before sending logs to the server."
        let error = NSError(domain: MFP_CORE_ERROR_DOMAIN, code: MFPErrorCode.ClientNotInitialized.rawValue, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        
        callback(nil, error)
    }
    
    
    internal func getLogs(fileName fileName: String, overflowFileName: String, bufferFileName: String) throws -> String? {
        
        let logFile = Logger.logsDocumentPath + fileName // Original log file
        let overflowLogFile = Logger.logsDocumentPath + overflowFileName // Extra file in case original log file got full
        let bufferLogFile = Logger.logsDocumentPath + bufferFileName // Temporary file for sending logs
        
        // First check if the "*.log.send" buffer file already contains logs. This will be the case if the previous attempt to send logs failed.
        if Logger.fileManager.isReadableFileAtPath(bufferLogFile) {
            return try readLogsFromFile(bufferLogFile)
        }
        else if Logger.fileManager.isReadableFileAtPath(logFile) {
            // Merge the logs from the normal log file and the overflow log file (if necessary)
            if Logger.fileManager.isReadableFileAtPath(overflowLogFile) {
                let fileContents = try NSString(contentsOfFile: overflowLogFile, encoding: NSUTF8StringEncoding) as String
                writeToFile(logFile, string: fileContents)
            }
            
            // Since the buffer log is empty, we move the log file to the buffer file in preparation of sending the logs. When new logs are recorded, a new log file gets created to replace it.
            try Logger.fileManager.moveItemAtPath(logFile, toPath: bufferLogFile)
            return try readLogsFromFile(bufferLogFile)
        }
        else {
            Logger.internalLogger.error("Cannot send data to server. Unable to read file: \(fileName).")
            return nil
        }
    }
    
    
    // We should only be sending logs from a buffer file, which is a copy of the normal log file. This way, if the logs fail to get sent to the server, we can hold onto them until the send succeeds, while continuing to log to the normal log file.
    internal func readLogsFromFile(bufferLogFile: String) throws -> String? {
        
        var fileContents: String?
        
        do {
            // Before sending the logs, we need to read them from the file. This is done in a serial dispatch queue to prevent conflicts if the log file is simulatenously being written to.
            switch bufferLogFile {
            case FILE_ANALYTICS_SEND:
                try dispatch_sync(Logger.analyticsFileIOQueue, block: { () -> () in
                    fileContents = try NSString(contentsOfFile: bufferLogFile, encoding: NSUTF8StringEncoding) as String
                })
            case FILE_LOGGER_SEND:
                try dispatch_sync(Logger.loggerFileIOQueue, block: { () -> () in
                    fileContents = try NSString(contentsOfFile: bufferLogFile, encoding: NSUTF8StringEncoding) as String
                })
            default:
                Logger.internalLogger.error("Cannot send data to server. Unrecognized file: \(bufferLogFile).")
            }
        }
        
        return fileContents
    }
    
    
    internal func deleteBufferFile(bufferFile: String) {
        
        if Logger.fileManager.isDeletableFileAtPath(bufferFile) {
            do {
                try Logger.fileManager.removeItemAtPath(bufferFile)
            }
            catch let error {
                Logger.internalLogger.error("Failed to delete log file \(bufferFile) after sending. Error: \(error)")
            }
        }
    }
    
    
    
    // MARK: Server configuration
    
    public func updateLogProfile(withCompletionHandler callback: MfpCompletionHandler? = nil) { }
    
    
    
    // MARK: Uncaught Exceptions
    
    // TODO: Make this private, and just document it? It looks like this is not part of the API in Android anyway.
    // TODO: In documentation, explain that developer must not set their own uncaught exception handler or this one will be overwritten
    private static func captureUncaughtExceptions() {
        
        NSSetUncaughtExceptionHandler { (caughtException: NSException) -> Void in
            
            // Persist a flag so that when the app starts back up, we can see if an exception occurred in the last session
            NSUserDefaults.standardUserDefaults().setBool(true, forKey: TAG_UNCAUGHT_EXCEPTION)
            
            Logger.logException(caughtException)
            existingUncaughtExceptionHandler?(caughtException)
        }
    }
    
    private static func logException(exception: NSException) {
        
        let logger = Logger.getLoggerForName(MFP_LOGGER_PACKAGE)
        var exceptionString = "Uncaught Exception: \(exception.name)."
        if let reason = exception.reason {
            exceptionString += " Reason: \(reason)."
        }
        logger.fatal(exceptionString)
    }

}


let existingUncaughtExceptionHandler = NSGetUncaughtExceptionHandler()


// MARK: FOUNDATION SDK

//
//@implementation OCLogger
//
//
//+(void) updateConfigFromServer{
//    @synchronized (self) {
//        WLRequestOptions *requestOptions = [[WLRequestOptions alloc] init];
//        [requestOptions setMethod:POST];
//        
//        NSMutableDictionary* headers = [NSMutableDictionary new];
//        
//        NSDictionary* deviceInfo = [OCLogger getDeviceInformation];
//        for(NSString* key in deviceInfo){
//            NSString *headerName = [NSString stringWithFormat:@"%@%@", @"x-wl-clientlog-", key];
//            [headers setObject:[deviceInfo valueForKey:key] forKey:headerName];
//        }
//        
//        [requestOptions setHeaders:headers];
//        
//        UpdateConfigDelegate *updateConfigDelegate = [UpdateConfigDelegate new];
//        WLRequest *updateConfigRequest = [(WLRequest *)[WLRequest alloc] initWithDelegate:updateConfigDelegate];
//        [updateConfigRequest makeRequestForRootUrl:CONFIG_URI_PATH withOptions:requestOptions];
//    }
//}
//
//+(void) processUpdateConfigFromServer:(int)statusCode withResponse:(NSString*)responseString
//{
//    @synchronized (self) {
//        NSDictionary* parsedResponse = [OCLoggerWorklight parseWorklightServerResponse:responseString];
//        
//        if(statusCode == HTTP_SC_OK){
//            NSLog(@"[DEBUG] [OCLogger] Logger configuration successfully retrieved from the server.");
//            [OCLogger processConfigResponseFromServer:parsedResponse];
//            
//        }else if(statusCode == HTTP_SC_NO_CONTENT){
//            NSLog(@"[DEBUG] [OCLogger] No matching client configuration profiles were found at the IBM MobileFirst Platform server. Logger now using local configurations.");
//            [OCLogger clearServerConfig];
//            
//        }
//    }
//}
//
//
//#pragma mark - Private Methods
//
//+(void) logWithLevel: (OCLogType) level
//andPackage: (NSString*) package
//andText: (NSString*) text
//andVariableArguments: (va_list) args
//andSkipLevelCheck: (BOOL) skipLevelFlag
//andTimestamp: (NSDate*) timestamp
//andMetadata:(NSDictionary*) metadata
//{
//    
//    if (![self canLogWithLevel:level withPackage:package]) {
//        return;
//    }
//    
//    // TODO just make a separate method for capturing analytics instead of all the branching
//    dispatch_sync(globalLoggerQueue, ^{
//        
//        NSString* levelTag = [OCLogger getLevelTag:level];
//        
//        NSString *msg = [OCLogger getMessageWith:text andArgs:args];
//        
//        if(level != OCLogger_ANALYTICS){
//            [OCLogger printMessage:msg withMetadata:metadata andLevelTag:levelTag andPackage:package];
//        }
//        
//        if (! [OCLogger shouldCaptureLog:level]) {
//            return;
//        }
//        
//        NSString* currentLogFile;
//        
//        if(level == OCLogger_ANALYTICS){
//            currentLogFile = [OCLogger getDocumentPath:FILENAME_ANALYTICS_LOG];
//        }else{
//            currentLogFile = [OCLogger getDocumentPath:FILENAME_WL_LOG];
//        }
//        
//        if (level != OCLogger_ANALYTICS &&
//            [[NSFileManager defaultManager] fileExistsAtPath:currentLogFile] &&
//            [OCLogger isFileSize:currentLogFile greaterThan:[OCLogger getMaxFileSize]]) {
//                [OCLogger swapLogFile];
//        }
//        
//        NSString* timestampStr = [OCLogger getCurrentTimestamp:timestamp];
//        
//        NSDictionary* dict = @{TAG_PKG : package,
//            TAG_TIMESTAMP : timestampStr,
//            TAG_LEVEL : levelTag,
//            TAG_MSG : msg,
//            TAG_META_DATA: metadata
//        };
//        [OCLogger writeString:[dict WLJSONRepresentation] toLogFile:currentLogFile];
//        });
//    
//}
//
//#pragma mark - Getters and Setters
//
//+(void) setCapture: (BOOL) flag
//{
//    NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
//    [standardUserDefaults setBool:flag forKey:TAG_CAPTURE];
//    [standardUserDefaults synchronize];
//}
//
//+(void) setServerCapture: (BOOL) flag
//{
//    NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
//    [standardUserDefaults setBool:flag forKey:TAG_SERVER_CAPTURE];
//    [standardUserDefaults synchronize];
//}
//
//+(BOOL) getCapture
//    {
//        if([OCLogger shouldUseServerConfig]){
//            return [[NSUserDefaults standardUserDefaults] boolForKey:TAG_SERVER_CAPTURE];
//        }
//        
//        return [[NSUserDefaults standardUserDefaults] boolForKey:TAG_CAPTURE];
//}
//
//+(void) setAnalyticsCapture: (BOOL) flag
//{
//    NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
//    [standardUserDefaults setBool:flag forKey:TAG_ANALYTICS_CAPTURE];
//    [standardUserDefaults synchronize];
//}
//
//+(BOOL) getAnalyticsCapture
//    {
//        return [[NSUserDefaults standardUserDefaults] boolForKey:TAG_ANALYTICS_CAPTURE];
//}
//
//+(void) processConfigResponseFromServer: (NSDictionary*) logConfig
//{
//    NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
//    [standardUserDefaults setBool:TRUE forKey:TAG_SERVER_CAPTURE];
//    
//    NSDictionary* wllogger =[logConfig objectForKey:@"wllogger"];
//    
//    if(wllogger != nil){
//        
//        NSDictionary* filters = [wllogger objectForKey:@"filters"];
//        
//        if(filters != nil){
//            [standardUserDefaults setObject:filters forKey:TAG_SERVER_FILTERS];
//        }
//        
//        NSString* level = [wllogger objectForKey:@"level"];
//        
//        if(level != nil){
//            OCLogType serverLevel = [OCLogger getLevelType:level];
//            [standardUserDefaults setInteger:serverLevel forKey:TAG_SERVER_LOG_LEVEL];
//        }
//    }
//    
//    [standardUserDefaults synchronize];
//}
//
//+(void)clearServerConfig{
//    NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
//    [standardUserDefaults removeObjectForKey:TAG_SERVER_CAPTURE];
//    [standardUserDefaults removeObjectForKey:TAG_SERVER_FILTERS];
//    [standardUserDefaults removeObjectForKey:TAG_SERVER_LOG_LEVEL];
//    [standardUserDefaults synchronize];
//}
//
//
//#pragma mark - Helper Functions
//
//
//+(NSDictionary*) getDeviceInformation
//    {
//        UIDevice* currentDevice = [UIDevice currentDevice];
//        
//        NSDictionary* deviceInfo = @{KEY_DEVICEINFO_ENV : [OCLoggerWorklight getWorklightEnvironment],
//            KEY_DEVICEINFO_OS_VERSION : [currentDevice systemVersion],
//            KEY_DEVICEINFO_MODEL : [OCLoggerWorklight getWorklightDeviceModel],
//            KEY_DEVICEINFO_APP_NAME : [OCLoggerWorklight getWorklightApplicationName],
//            KEY_DEVICEINFO_APP_VERSION : [OCLoggerWorklight getWorklightApplicationVersion],
//            KEY_DEVICEINFO_DEVICE_ID : [OCLoggerWorklight getWorklightDeviceId]
//        };
//        
//        return deviceInfo;
//}
//
//+(NSURL*) getWorklightPostURL
//    {
//        return [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", [OCLoggerWorklight getWorklightBaseURL], LOG_UPLOADER_PATH]];
//}
//
//+(BOOL) shouldUseServerConfig
//    {
//        NSObject *serverConfigSet = [[NSUserDefaults standardUserDefaults] objectForKey:TAG_SERVER_CAPTURE];
//        return (serverConfigSet != NULL);
//}
//
//+(BOOL) isFileSize:(NSString*) filePath greaterThan:(int) max
//{
//    NSError* error = nil;
//    long long sizeAtPath = [[[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:&error][NSFileSize] longLongValue];
//    if (error) {
//        NSLog(@"[DEBUG] [OCLogger] Failed with error: %@, getting the file size for path: %@", error, filePath);
//    }
//    
//    if(sizeAtPath > max) {
//        NSLog(@"[DEBUG] [OCLogger] Max file size exceeded for log messages.");
//        return true;
//    }
//    
//    return false;
//}
//
//+(NSFileHandle*) getHandleAtEndOfFileWithPath:(NSString*) path
//{
//    NSFileHandle *myHandle = [NSFileHandle fileHandleForWritingAtPath:path];
//    
//    if (myHandle == nil) {
//        
//        //file not found, create it
//        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
//        myHandle = [NSFileHandle fileHandleForWritingAtPath:path];
//        
//    }
//    
//    [myHandle seekToEndOfFile];
//    
//    return myHandle;
//}
//
//@end
//
//
//#pragma mark - Delegate Implementations
//@implementation UpdateConfigDelegate
//
//// TODO to be removed when piggybacker is done
//-(void)onSuccessWithResponse:(WLResponse *)response userInfo:(NSDictionary *)userInfo{
//    [OCLogger processUpdateConfigFromServer:response.status withResponse:response.responseText];
//}
//
//-(void)onFailureWithResponse:(WLFailResponse *)response userInfo:(NSDictionary *)userInfo{
//    NSLog(@"[DEBUG] [OCLogger] Request to update configuration profile has failed.");
//}
//@end
//
//
