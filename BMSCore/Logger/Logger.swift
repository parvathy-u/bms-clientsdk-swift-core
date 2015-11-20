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

// TODO: Log only the file name, not the whole path

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
    
    internal static let logsDocumentPath: String = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0] + "/"
    
    private static let fileManager = NSFileManager.defaultManager()
    
    
    
    // MARK: Dispatch queues
    
    private static let loggerFileIOQueue: dispatch_queue_t = dispatch_queue_create("com.ibm.mobilefirstplatform.clientsdk.swift.BMSCore.Logger.loggerFileIOQueue", DISPATCH_QUEUE_SERIAL)
    
    
    private static let analyticsFileIOQueue: dispatch_queue_t = dispatch_queue_create("com.ibm.mobilefirstplatform.clientsdk.swift.BMSCore.Logger.analyticsFileIOQueue", DISPATCH_QUEUE_SERIAL)
    
    
    private static let sendLogsToServerQueue: dispatch_queue_t = dispatch_queue_create("com.ibm.mobilefirstplatform.clientsdk.swift.BMSCore.Logger.sendLogsToServerQueue", DISPATCH_QUEUE_SERIAL)
    
    
    private static let sendAnalyticsToServerQueue: dispatch_queue_t = dispatch_queue_create("com.ibm.mobilefirstplatform.clientsdk.swift.BMSCore.Logger.sendAnalyticsToServerQueue", DISPATCH_QUEUE_SERIAL)
    
    
    private static let updateLogProfileQueue: dispatch_queue_t = dispatch_queue_create("com.ibm.mobilefirstplatform.clientsdk.swift.BMSCore.Logger.updateLogProfileQueue", DISPATCH_QUEUE_SERIAL)

    
    // Custom dispatch_sync that can incorporate throwable statements
    internal static func dispatch_sync(queue: dispatch_queue_t, block: () throws -> ()) throws {
        
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
    
    public static var maxLogStoreSize: UInt64 {
        get {
            return NSUserDefaults.standardUserDefaults().objectForKey(TAG_MAX_STORE_SIZE) as? UInt64 ?? DEFAULT_MAX_STORE_SIZE
        }
        set {
            let valueAsObject = NSNumber(unsignedLongLong: newValue)
            NSUserDefaults.standardUserDefaults().setObject(valueAsObject, forKey: TAG_MAX_STORE_SIZE)
        }
    }
    
    public static var isUncaughtExceptionDetected: Bool {
        get {
            return NSUserDefaults.standardUserDefaults().boolForKey(TAG_UNCAUGHT_EXCEPTION)
        }
        set {
            NSUserDefaults.standardUserDefaults().setBool(newValue, forKey: TAG_UNCAUGHT_EXCEPTION)
        }
    }
    
    public static var internalSDKLoggingEnabled: Bool {
        get {
            return false
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
    public func debug(message: String, file: String = __FILE__, function: String = __FUNCTION__, line: Int = __LINE__) {
        
        logMessage(message, level: LogLevel.Debug, calledFile: file, calledFunction: function, calledLineNumber: line)
    }
    
    
    public func info(message: String, file: String = __FILE__, function: String = __FUNCTION__, line: Int = __LINE__) {
    
        logMessage(message, level: LogLevel.Info, calledFile: file, calledFunction: function, calledLineNumber: line)
    }
    
    
    public func warn(message: String, file: String = __FILE__, function: String = __FUNCTION__, line: Int = __LINE__) {
        
        logMessage(message, level: LogLevel.Warn, calledFile: file, calledFunction: function, calledLineNumber: line)
    }
    
    
    public func error(message: String, file: String = __FILE__, function: String = __FUNCTION__, line: Int = __LINE__) {
        
        logMessage(message, level: LogLevel.Error, calledFile: file, calledFunction: function, calledLineNumber: line)
    }
    
    
    public func fatal(message: String, file: String = __FILE__, function: String = __FUNCTION__, line: Int = __LINE__) {
        
        logMessage(message, level: LogLevel.Fatal, calledFile: file, calledFunction: function, calledLineNumber: line)
    }
    
    
    internal func analytics(metadata: [String: AnyObject], file: String = __FILE__, function: String = __FUNCTION__, line: Int = __LINE__) {
        
        logMessage("", level: LogLevel.Analytics, calledFile: file, calledFunction: function, calledLineNumber: line, additionalMetadata: metadata)
    }
    
    
    internal static func printLogToConsole(logMessage: String, loggerName: String, level: LogLevel, calledFunction: String, calledFile: String, calledLineNumber: Int) {
        
        if level != LogLevel.Analytics {
            print("[\(level.stringValue)] [\(loggerName)] \(calledFunction) in \(calledFile):\(calledLineNumber) :: \(logMessage)")
        }
    }
    
    
    internal func logMessage(message: String, level: LogLevel, calledFile: String, calledFunction: String, calledLineNumber: Int, additionalMetadata: [String: AnyObject]? = nil) {
        
        // TODO: dispatch_async?
        
        guard canLogAtLevel(level) else {
            return
        }
        
        // Print to console
        // Example: [DEBUG] [mfpsdk.logger] logMessage in Logger.swift:234 :: "Some random message"
        Logger.printLogToConsole(message, loggerName: self.name, level: level, calledFunction: calledFunction, calledFile: calledFile, calledLineNumber: calledLineNumber)
        
        // Get file names
        var logFile: String = Logger.logsDocumentPath
        var logOverflowFile: String = Logger.logsDocumentPath
        if level == LogLevel.Analytics {
            logFile += FILE_LOGGER_LOGS
            logOverflowFile += FILE_LOGGER_OVERFLOW
        }
        else {
            logFile += FILE_ANALYTICS_LOGS
            logOverflowFile += FILE_ANALYTICS_OVERFLOW
        }
        
        // Check if the log file is larger than the maxLogStoreSize. If so, move the log file to the "overflow" file, and start logging to a new log file. If an overflow file already exists, those logs get overwritten.
        if fileLogIsFull(logFile) {
            do {
                try moveOldLogsToOverflowFile(logFile, overflowFile: logOverflowFile)
            }
            catch let error {
                NSLog("Log file \(logFile) is full but the old logs could not be removed. Try sending the logs. Error: \(error)")
                return
            }
        }
        
        let timeStampString = Logger.dateFormatter.stringFromDate(NSDate())
        let logAsJsonString = convertLogToJson(message, level: level, timeStamp: timeStampString, additionalMetadata: additionalMetadata)
        
        guard logAsJsonString != nil else {
            let errorMessage = "Failed to write logs to file. This is likely because the analytics metadata could not be parsed."
            Logger.printLogToConsole(errorMessage, loggerName:self.name, level: .Error, calledFunction: __FUNCTION__, calledFile: __FILE__, calledLineNumber: __LINE__)
            return
        }
        
        Logger.writeToFile(logFile, string: logAsJsonString!, loggerName: self.name)
    }
    
    
    internal func fileLogIsFull(logFileName: String) -> Bool {
        
        if (Logger.fileManager.fileExistsAtPath(logFileName)) {
            
            do {
                let fileAttributes = try Logger.fileManager.attributesOfItemAtPath(logFileName)
                if let currentLogFileSize = fileAttributes[NSFileSystemSize] as? UInt64 {
                    return currentLogFileSize > Logger.maxLogStoreSize / 2 // Divide by 2 since the total log storage gets shared between the log file and the overflow file
                }
            }
            catch let error {
                NSLog("Cannot determine the size of file:\(logFileName) due to error: \(error). In case the file size is greater than the specified max log storage size, logs will not be written to file.")
            }
        }
        
        return false
    }
    
    
    internal func moveOldLogsToOverflowFile(logFile: String, overflowFile: String) throws {
        
        if Logger.fileManager.isDeletableFileAtPath(overflowFile) {
            try Logger.fileManager.removeItemAtPath(overflowFile)
        }
        try Logger.fileManager.moveItemAtPath(logFile, toPath: overflowFile)
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
    
    
    // Convert log message and metadata into JSON format. This is the actual string that gets written to the log files.
    internal func convertLogToJson(logMessage: String, level: LogLevel, timeStamp: String, additionalMetadata: [String: AnyObject]?) -> String? {
        
        var logMetadata: [String: AnyObject] = [:]
        logMetadata["timestamp"] = timeStamp
        logMetadata["level"] = level.stringValue
        logMetadata["pkg"] = self.name
        logMetadata["msg"] = logMessage
        if additionalMetadata != nil {
            logMetadata["metadata"] = additionalMetadata!
        }

        let logData: NSData
        do {
            logData = try NSJSONSerialization.dataWithJSONObject(logMetadata, options: [])
        }
        catch {
            return nil
        }
        
        return String(data: logData, encoding: NSUTF8StringEncoding)
    }
    
    
    internal static func writeToFile(file: String, string: String, loggerName: String) {
        
        if !Logger.fileManager.fileExistsAtPath(file) {
            Logger.fileManager.createFileAtPath(file, contents: nil, attributes: nil)
        }
        
        let fileHandle = NSFileHandle(forWritingAtPath: file)
        let data = string.dataUsingEncoding(NSUTF8StringEncoding)
        if fileHandle != nil && data != nil {
            fileHandle!.seekToEndOfFile()
            fileHandle!.writeData(data!)
        }
        else {
            let errorMessage = "Cannot write to file: \(file)."
            printLogToConsole(errorMessage, loggerName: loggerName, level: LogLevel.Error, calledFunction: __FUNCTION__, calledFile: __FILE__, calledLineNumber: __LINE__)
        }
    }
    
    
    
    // MARK: Uncaught Exceptions
    
    private static let existingUncaughtExceptionHandler = NSGetUncaughtExceptionHandler()
    private static var exceptionHasBeenCalled = false
    
    
    // TODO: Make this private, and just document it? It looks like this is not part of the API in Android anyway.
    // TODO: In documentation, explain that developer must not set their own uncaught exception handler or this one will be overwritten
    private static func captureUncaughtExceptions() {
        
        NSSetUncaughtExceptionHandler { (caughtException: NSException) -> Void in
            
            if (!Logger.exceptionHasBeenCalled) {
                Logger.exceptionHasBeenCalled = true
                Logger.logException(caughtException)
                // Persist a flag so that when the app starts back up, we can see if an exception occurred in the last session
                Logger.isUncaughtExceptionDetected = true
                Logger.existingUncaughtExceptionHandler?(caughtException)
            }
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
    
    
    
    // MARK: Sending logs
    
    public static func send(completionHandler userCallback: MfpCompletionHandler? = nil) {
        
        let logSendCallback: MfpCompletionHandler = { (response: Response?, error: NSError?) in
            if error != nil {
                Logger.internalLogger.debug("Client logs successfully sent to the server.")
                // Remove the uncaught exception flag since the logs containing the exception(s) have just been sent to the server
                NSUserDefaults.standardUserDefaults().setBool(false, forKey: TAG_UNCAUGHT_EXCEPTION)
                deleteBufferFile(FILE_LOGGER_SEND)
                Logger.isUncaughtExceptionDetected = false
            }
            else {
                Logger.internalLogger.error("Request to send client logs has failed.")
            }
            
            userCallback?(response, error)
        }
        
        // Use a serial queue to ensure that the same logs do not get sent more than once
        dispatch_async(Logger.sendLogsToServerQueue) { () -> Void in
            do {
                let logsToSend: String? = try getLogs(fileName: FILE_LOGGER_LOGS, overflowFileName: FILE_LOGGER_OVERFLOW, bufferFileName: FILE_LOGGER_SEND)
                if logsToSend != nil {
                    sendToServer(logsToSend!, withCallback: logSendCallback)
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
    
    
    internal static func sendAnalytics(completionHandler userCallback: MfpCompletionHandler? = nil) {
    
        // Internal completion handler - wraps around the user supplied completion handler (if supplied)
        let analyticsSendCallback: MfpCompletionHandler = { (response: Response?, error: NSError?) in
            if error != nil {
                Analytics.logger.debug("Analytics data successfully sent to the server.")
           deleteBufferFile(FILE_ANALYTICS_SEND)
            }
            else {
                Analytics.logger.error("Request to send analytics data to the server has failed.")
            }
            
            userCallback?(response, error)
        }
        
        // Use a serial queue to ensure that the same analytics data do not get sent more than once
        dispatch_async(Logger.sendAnalyticsToServerQueue) { () -> Void in
            do {
                let logsToSend: String? = try getLogs(fileName: FILE_ANALYTICS_LOGS, overflowFileName:FILE_ANALYTICS_OVERFLOW, bufferFileName: FILE_ANALYTICS_SEND)
                if logsToSend != nil {
                    sendToServer(logsToSend!, withCallback: analyticsSendCallback)
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
    
    
    internal static func sendToServer(logs: String, withCallback callback: MfpCompletionHandler) {
        
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
    
    private static func returnClientInitializationError(missingValue: String, callback: MfpCompletionHandler) {
        
        Logger.internalLogger.error("No value found for the BMSClient \(missingValue) property.")
        let errorMessage = "Must initialize BMSClient before sending logs to the server."
        let error = NSError(domain: MFP_CORE_ERROR_DOMAIN, code: MFPErrorCode.ClientNotInitialized.rawValue, userInfo: [NSLocalizedDescriptionKey: errorMessage])
        
        callback(nil, error)
    }
    
    
    internal static func getLogs(fileName fileName: String, overflowFileName: String, bufferFileName: String) throws -> String? {
        
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
                writeToFile(logFile, string: fileContents, loggerName: Logger.internalLogger.name)
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
    internal static func readLogsFromFile(bufferLogFile: String) throws -> String? {
        
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
    
    
    internal static func deleteBufferFile(bufferFile: String) {
        
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

}

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
//#pragma mark - Getters and Setters
//
//+(void) setCapture: (BOOL) flag
//{
//    NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
//    [standardUserDefaults setBool:flag forKey:TAG_CAPTURE];
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
//
//+(BOOL) shouldUseServerConfig
//    {
//        NSObject *serverConfigSet = [[NSUserDefaults standardUserDefaults] objectForKey:TAG_SERVER_CAPTURE];
//        return (serverConfigSet != NULL);
//}
//
//
//#pragma mark - Delegate Implementations
//@implementation UpdateConfigDelegate
//
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
