//
//  TraktManager.swift
//  TVShows
//
//  Created by Maximilian Litteral on 2/4/15.
//  Copyright (c) 2015 Maximilian Litteral. All rights reserved.
//

import Foundation

// Errors
internal let userInfo = [
    "title": "Trakt",
    NSLocalizedDescriptionKey: "No data returned",
    NSLocalizedFailureReasonErrorKey: "",
    NSLocalizedRecoverySuggestionErrorKey: ""
]
let TraktKitNoDataError = NSError(domain: "com.litteral.TraktKit", code: -10, userInfo: userInfo)

// Enums

public enum Method: String {
    /// Select one or more items. Success returns 200 status code.
    case GET
    /// Create a new item. Success returns 201 status code.
    case POST
    /// Update an item. Success returns 200 status code.
    case PUT
    /// Delete an item. Success returns 200 or 204 status code.
    case DELETE
}

public struct StatusCodes {
    /// Success
    public static let Success = 200
    /// Success - new resource created (POST)
    public static let SuccessNewResourceCreated = 201
    /// Success - no content to return (DELETE)
    public static let SuccessNoContentToReturn = 204
    /// Bad Request - request couldn't be parsed
    public static let BadRequestion = 400
    /// Unauthorized - OAuth must be provided
    public static let Unauthorized = 401
    /// Forbidden - invalid API key or unapproved app
    public static let Forbidden = 403
    /// Not Found - method exists, but no record found
    public static let NotFound = 404
    /// Method Not Found - method doesn't exist
    public static let MethodNotFound = 405
    /// Conflict - resource already created
    public static let Conflict = 409
    /// Precondition Failed - use application/json content type
    public static let PreconditionFailed = 412
    /// Unprocessable Entity - validation errors
    public static let UnprocessableEntity = 422
    /// Rate Limit Exceeded
    public static let RateLimitExceeded = 429
    /// Server Error
    public static let ServerError = 500
    /// Service Unavailable - server overloaded
    public static let ServiceOverloaded = 503
    /// Service Unavailable - Cloudflare error
    public static let CloudflareError = 520
    /// Service Unavailable - Cloudflare error
    public static let CloudflareError2 = 521
    /// Service Unavailable - Cloudflare error
    public static let CloudflareError3 = 522
}

public enum SearchType: String {
    case Movie = "movie"
    case Show = "show"
    case Episode = "episode"
    case Person = "person"
    case List = "list"
}

public enum LookupType: String {
    case TraktMovie = "trakt-movie"
    case TraktShow = "trakt-show"
    case TraktEpisode = "trakt-episode"
    case IMDB = "imdb"
    case TMDB = "tmdb"
    case TVDB = "tvdb"
    case TVRage = "tvrage"
}

public enum Type: String, CustomStringConvertible {
    case Movies = "movies"
    case Shows = "shows"
    
    public var description: String {
        return self.rawValue
    }
}

public enum WatchedType: String, CustomStringConvertible {
    case Movies = "movies"
    case Shows = "shows"
    case Seasons = "seasons"
    case Episodes = "episodes"
    
    public var description: String {
        return self.rawValue
    }
}

public enum Type2: String, CustomStringConvertible {
    case All = "all"
    case Movies = "movies"
    case Shows = "shows"
    case Seasons = "seasons"
    case Episodes = "episodes"
    case Lists = "lists"
    
    public var description: String {
        return self.rawValue
    }
}

public enum CommentType: String {
    case All = "all"
    case Reviews = "reviews"
    case Shouts = "shouts"
}

public enum extendedType: String {
    case Min = "min"
    case Images = "images"
    case Full = "full"
    case FullAndImages = "full,images"
    case Metadata = "metadata"
    case Episodes = "episodes" // For getting all seasons and episodes
    case FullAndEpisodes = "full,episodes"
    case FullAndEpisodesAndImages = "full,episodes,images"
}

public class TraktManager {
    
    // TODO List:
    // 1. Create a limit object, double check every paginated API call is marked as paginated
    
    // MARK: Internal
    private var clientID: String?
    private var clientSecret: String?
    private var redirectURI: String?
    
    // Keys
    let accessTokenKey = "accessToken"
    let refreshTokenKey = "refreshToken"
    
    // Lazy
    lazy var session = NSURLSession(configuration: NSURLSessionConfiguration.defaultSessionConfiguration())
    
    // MARK: Public
    public static let sharedManager = TraktManager()
    
    public var isSignedIn: Bool {
        get {
            return accessToken != nil
        }
    }
    public var oauthURL: NSURL?
    
    public var accessToken: String? {
        get {
            if let accessTokenData = MLKeychain.loadData(forKey: accessTokenKey) {
                if let accessTokenString = NSString(data: accessTokenData, encoding: NSUTF8StringEncoding) as? String {
                    return accessTokenString
                }
            }
            
            return nil
        }
        set {
            // Save somewhere secure
            
            if newValue == nil {
                // Remove from keychain
                MLKeychain.deleteItem(forKey: accessTokenKey)
            }
            else {
                // Save to keychain
                let succeeded = MLKeychain.setString(newValue!, forKey: accessTokenKey)
                #if DEBUG
                    print("Saved access token: \(succeeded)")
                #endif
            }
        }
    }
    
    public var refreshToken: String? {
        get {
            if let refreshTokenData = MLKeychain.loadData(forKey: refreshTokenKey) {
                if let accessTokenString = NSString(data: refreshTokenData, encoding: NSUTF8StringEncoding) as? String {
                    return accessTokenString
                }
            }
            
            return nil
        }
        set {
            // Save somewhere secure
            if newValue == nil {
                // Remove from keychain
                MLKeychain.deleteItem(forKey: refreshTokenKey)
            }
            else {
                // Save to keychain
                let succeeded = MLKeychain.setString(newValue!, forKey: refreshTokenKey)
                #if DEBUG
                    print("Saved refresh token: \(succeeded)")
                #endif
            }
        }
    }
    
    // Completion handlers
    public typealias arrayCompletionHandler         = (objects: [[String: AnyObject]]?, error: NSError?) -> Void
    public typealias dictionaryCompletionHandler    = (dictionary: [String: AnyObject]?, error: NSError?) -> Void
    public typealias successCompletionHandler       = (success: Bool) -> Void
    public typealias commentsCompletionHandler      = ((comments: [Comment], error: NSError?) -> Void)
    public typealias CastCrewCompletionHandler      = ((cast: [CastMember], crew: [CrewMember], error: NSError?) -> Void)
    
    // MARK: - Lifecycle
    
    private init() {
        #if DEBUG
            assert(clientID == nil, "Client ID needs to be set")
            assert(clientSecret == nil, "Client secret needs to be set")
            assert(redirectURI == nil, "Redirect URI needs to be set")
        #endif
        
    }
    
    // MARK: - Setup
    
    public func setClientID(clientID: String, clientSecret secret: String, redirectURI: String) {
        self.clientID = clientID
        self.clientSecret = secret
        self.redirectURI = redirectURI
        
        self.oauthURL = NSURL(string: "https://trakt.tv/oauth/authorize?response_type=code&client_id=\(clientID)&redirect_uri=\(redirectURI)")
    }
    
    internal func createTraktErrorWithStatusCode(statusCode: Int) -> NSError {
        let userInfo = [
            "title": "Trakt",
            NSLocalizedDescriptionKey: "Request Failed: Gateway timed out (\(statusCode))",
            NSLocalizedFailureReasonErrorKey: "",
            NSLocalizedRecoverySuggestionErrorKey: ""
        ]
        let TraktKitIncorrectStatusError = NSError(domain: "com.litteral.TraktKit", code: statusCode, userInfo: userInfo)
        
        return TraktKitIncorrectStatusError
    }
    
    // MARK: - Actions
    
    public func mutableRequestForURL(URL: NSURL?, authorization: Bool, HTTPMethod: Method) -> NSMutableURLRequest? {
        let request = NSMutableURLRequest(URL: URL!)
        request.HTTPMethod = HTTPMethod.rawValue
        
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2", forHTTPHeaderField: "trakt-api-version")
        if let clientID = clientID {
            request.addValue(clientID, forHTTPHeaderField: "trakt-api-key")
        }
        
        if authorization {
            if let accessToken = accessToken {
                request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            else {
                return nil
            }
        }
        
        return request
    }
    
    public func mutableRequestForURL(path: String, authorization: Bool, HTTPMethod: Method) -> NSMutableURLRequest? {
        let urlString = "https://api-v2launch.trakt.tv/" + path
        guard let URL = NSURL(string: urlString) else {
            return nil
        }
        let request = NSMutableURLRequest(URL: URL)
        request.HTTPMethod = HTTPMethod.rawValue
        
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("2", forHTTPHeaderField: "trakt-api-version")
        if let clientID = clientID {
            request.addValue(clientID, forHTTPHeaderField: "trakt-api-key")
        }
        
        if authorization {
            if let accessToken = accessToken {
                request.addValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            else {
                return nil
            }
        }
        
        return request
    }
    
    func createJsonData(movies movies: [RawJSON], shows: [RawJSON], episodes: [RawJSON]) throws -> NSData? {
        
        let json = [
            "movies": movies,
            "shows": shows,
            "episodes": episodes,
        ]
        
        #if DEBUG
            print(json)
        #endif
        return try NSJSONSerialization.dataWithJSONObject(json, options: NSJSONWritingOptions(rawValue: 0))
    }
    
    // MARK: Perform Requests
    
    func performRequest(request request: NSURLRequest, expectingStatusCode code: Int, completion: arrayCompletionHandler) -> NSURLSessionDataTask? {
        let dataTask = session.dataTaskWithRequest(request) { [weak self] (data, response, error) -> Void in
            guard let wSelf = self else { return }
            guard error == nil else {
                #if DEBUG
                    print("[\(#function)] \(error!)")
                #endif
                completion(objects: nil, error: error)
                return
            }
            
            // Check response
            guard let HTTPResponse = response as? NSHTTPURLResponse
                where HTTPResponse.statusCode == code else {
                    #if DEBUG
                        print(response)
                    #endif
    
                    if let HTTPResponse = response as? NSHTTPURLResponse {
                        completion(objects: nil, error: wSelf.createTraktErrorWithStatusCode(HTTPResponse.statusCode))
                    }
                    else {
                        completion(objects: nil, error: nil)
                    }
                    
                    return
            }
            
            // Check data
            guard let data = data else {
                completion(objects: nil, error: TraktKitNoDataError)
                return
            }
            
            do {
                if let array = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions(rawValue: 0)) as? [[String: AnyObject]] {
                    completion(objects: array, error: nil)
                }
            }
            catch let jsonSerializationError as NSError {
                #if DEBUG
                    print(jsonSerializationError)
                #endif
                completion(objects: nil, error: jsonSerializationError)
            }
        }
        
        dataTask.resume()
        return dataTask
    }
    
    func performRequest(request request: NSURLRequest, expectingStatusCode code: Int, completion: dictionaryCompletionHandler) -> NSURLSessionDataTask? {
        let datatask = session.dataTaskWithRequest(request) { [weak self] (data, response, error) -> Void in
            guard let wSelf = self else { return }
            guard error == nil else {
                #if DEBUG
                    print("[\(#function)] \(error!)")
                #endif
                completion(dictionary: nil, error: error)
                return
            }
            
            // Check response
            guard let HTTPResponse = response as? NSHTTPURLResponse
                where HTTPResponse.statusCode == code else {
                    #if DEBUG
                        print(response)
                    #endif
                    
                    if let HTTPResponse = response as? NSHTTPURLResponse {
                        completion(dictionary: nil, error: wSelf.createTraktErrorWithStatusCode(HTTPResponse.statusCode))
                    }
                    else {
                        completion(dictionary: nil, error: nil)
                    }
                    return
            }
            
            // Check data
            guard let data = data else {
                completion(dictionary: nil, error: TraktKitNoDataError)
                return
            }
            
            do {
                if let dict = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions(rawValue: 0)) as? [String: AnyObject] {
                    completion(dictionary: dict, error: nil)
                }
            }
            catch let jsonSerializationError as NSError {
                #if DEBUG
                    print("[\(#function)] \(jsonSerializationError)")
                #endif
                completion(dictionary: nil, error: jsonSerializationError)
            }
        }
        datatask.resume()
        
        return datatask
    }
    
    func performRequest(request request: NSURLRequest, expectingStatusCode code: Int, completion: successCompletionHandler) -> NSURLSessionDataTask? {
        let datatask = session.dataTaskWithRequest(request) { (data, response, error) -> Void in
            guard error == nil else {
                #if DEBUG
                    print("[\(#function)] \(error!)")
                #endif
                
                completion(success: false)
                return
            }
            
            // Check response
            guard let HTTPResponse = response as? NSHTTPURLResponse
                where HTTPResponse.statusCode == code else {
                    #if DEBUG
                        print("[\(#function)] \(response)")
                    #endif
                    
                    completion(success: false)
                    
                    return
            }
            
            // Check data
            guard data != nil else {
                completion(success: false)
                return
            }
            
            completion(success: true)
        }
        datatask.resume()
        
        return datatask
    }
    
    func performRequest(request request: NSURLRequest, expectingStatusCode code: Int, completion: commentsCompletionHandler) -> NSURLSessionDataTask? {
        let aCompletion: arrayCompletionHandler = { (objects: [[String: AnyObject]]?, error: NSError?) -> Void in
            
            if let objects = objects {
                var comments: [Comment] = []
                
                for jsonComment in objects {
                    let comment = Comment(json: jsonComment)
                    
                    comments.append(comment)
                }
                
                completion(comments: comments, error: error)
            }
            else {
                completion(comments: [], error: error)
            }
        }
        
        let dataTask = performRequest(request: request, expectingStatusCode: StatusCodes.Success, completion: aCompletion)
        
        return dataTask
    }
    
    func performRequest(request request: NSURLRequest, expectingStatusCode code: Int, completion: CastCrewCompletionHandler) -> NSURLSessionDataTask? {
        let aCompletion: dictionaryCompletionHandler = { (json: [String: AnyObject]?, error: NSError?) -> Void in
            guard let json = json else { return completion(cast: [], crew: [], error: error) }
            
            var crew: [CrewMember] = []
            var cast: [CastMember] = []
            
            // Crew
            if let jsonCrew = json["crew"] as? RawJSON {
                
                func addMembers(members: [RawJSON]) {
                    members.forEach { (dict) in
                        let crewMember = CrewMember(json: dict)
                        crew.append(crewMember)
                    }
                }
                
                if let members = jsonCrew["production"] as? [RawJSON] { addMembers(members) }
                if let members = jsonCrew["writing"] as? [RawJSON] { addMembers(members) }
                if let members = jsonCrew["crew"] as? [RawJSON] { addMembers(members) }
                if let members = jsonCrew["camera"] as? [RawJSON] { addMembers(members) }
                if let members = jsonCrew["sound"] as? [RawJSON] { addMembers(members) }
            }
            
            // Cast
            if let members = json["cast"] as? [[String: AnyObject]] {
                members.forEach { (dict) in
                    let castMember = CastMember(json: dict)
                    cast.append(castMember)
                }
            }
            
            completion(cast: cast, crew: crew, error: error)
        }
        
        let dataTask = performRequest(request: request, expectingStatusCode: StatusCodes.Success, completion: aCompletion)
        
        return dataTask
    }
    
    // MARK: - Authentication
    
    public func getTokenFromAuthorizationCode(code: String, completionHandler: successCompletionHandler?) throws {
        guard let clientID = clientID,
            clientSecret = clientSecret,
            redirectURI = redirectURI else {
                completionHandler?(success: false)
                return
        }
        
        let urlString = "https://trakt.tv/oauth/token"
        let url = NSURL(string: urlString)
        guard let request = mutableRequestForURL(url, authorization: false, HTTPMethod: .POST) else {
            completionHandler?(success: false)
            return
        }
        
        let json = [
            "code": code,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
        ]
        
        request.HTTPBody = try NSJSONSerialization.dataWithJSONObject(json, options: NSJSONWritingOptions(rawValue: 0))
        
        let dataTask = session.dataTaskWithRequest(request) { [weak self] (data, response, error) -> Void in
            guard let wSelf = self else { return }
            guard error == nil else {
                #if DEBUG
                    print("[\(#function)] \(error!)")
                #endif
                
                completionHandler?(success: false)
                
                return
            }
            
            // Check response
            guard let HTTPResponse = response as? NSHTTPURLResponse
                where HTTPResponse.statusCode == StatusCodes.Success else {
                    #if DEBUG
                        print("[\(#function)] \(response)")
                    #endif
                    completionHandler?(success: false)
                    return
            }
            
            // Check data
            guard let data = data else {
                completionHandler?(success: false)
                return
            }
            
            do {
                if let accessTokenDict = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions(rawValue: 0)) as? [String: AnyObject] {
                    
                    wSelf.accessToken = accessTokenDict["access_token"] as? String
                    wSelf.refreshToken = accessTokenDict["refresh_token"] as? String
                    
                    #if DEBUG
                        print("[\(#function)] Access token is \(wSelf.accessToken)")
                        print("[\(#function)] Refresh token is \(wSelf.refreshToken)")
                    #endif
                    
                    // Save expiration date
                    let timeInterval = accessTokenDict["expires_in"] as! NSNumber
                    let expiresDate = NSDate(timeIntervalSinceNow: timeInterval.doubleValue)
                    
                    NSUserDefaults.standardUserDefaults().setObject(expiresDate, forKey: "accessTokenExpirationDate")
                    NSUserDefaults.standardUserDefaults().synchronize()
                    
                    // Post notification
                    NSOperationQueue.mainQueue().addOperationWithBlock({ () -> Void in
                        NSNotificationCenter.defaultCenter().postNotificationName("signedInToTrakt", object: nil)
                    })
                    
                    completionHandler?(success: true)
                }
            }
            catch let jsonSerializationError as NSError {
                #if DEBUG
                    print("[\(#function)] \(jsonSerializationError)")
                #endif
                completionHandler?(success: false)
            }
        }
        dataTask.resume()
    }
    
    // MARK: Refresh access token
    
    public func needToRefresh() -> Bool {
        if let expirationDate = NSUserDefaults.standardUserDefaults().objectForKey("accessTokenExpirationDate") as? NSDate {
            let today = NSDate()
            
            if today.compare(expirationDate) == .OrderedDescending ||
                today.compare(expirationDate) == .OrderedSame {
                    return true
            }
            else {
                return false
            }
        }
        
        return false
    }
    
    public func checkToRefresh() throws {
        if let expirationDate = NSUserDefaults.standardUserDefaults().objectForKey("accessTokenExpirationDate") as? NSDate {
            let today = NSDate()
            
            if today.compare(expirationDate) == .OrderedDescending ||
                today.compare(expirationDate) == .OrderedSame {
                    #if DEBUG
                        print("[\(#function)] Refreshing token!")
                    #endif
                    try self.getAccessTokenFromRefreshToken({ (success) -> Void in
                        
                    })
            }
            else {
                #if DEBUG
                    print("[\(#function)] No need to refresh token!")
                #endif
            }
        }
    }
    
    public func getAccessTokenFromRefreshToken(completionHandler: successCompletionHandler) throws {
        guard let clientID = clientID,
            clientSecret = clientSecret,
            redirectURI = redirectURI else {
                completionHandler(success: false)
                return
        }
        
        guard let rToken = refreshToken else {
            #if DEBUG
                print("[\(#function)] Refresh token is nil")
            #endif
            completionHandler(success: false)
            return
        }
        
        let urlString = "https://trakt.tv/oauth/token"
        let url = NSURL(string: urlString)
        guard let request = mutableRequestForURL(url, authorization: false, HTTPMethod: .POST) else {
            completionHandler(success: false)
            return
        }
        
        let json = [
            "refresh_token": rToken,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "refresh_token",
        ]
        request.HTTPBody = try NSJSONSerialization.dataWithJSONObject(json, options: NSJSONWritingOptions(rawValue: 0))
        
        session.dataTaskWithRequest(request) { (data, response, error) -> Void in
            guard error == nil else {
                #if DEBUG
                    print("[\(#function)] \(error!)")
                #endif
                completionHandler(success: false)
                return
            }
            
            // Check response
            guard let HTTPResponse = response as? NSHTTPURLResponse
                where HTTPResponse.statusCode == StatusCodes.Success else {
                #if DEBUG
                    print("[\(#function)] \(response)")
                #endif
                completionHandler(success: false)
                return
            }
            
            // Check data
            guard let data = data else {
                completionHandler(success: false)
                return
            }
            
            do {
                if let accessTokenDict = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions(rawValue: 0)) as? [String: AnyObject] {
                    
        
                    self.accessToken = accessTokenDict["access_token"] as? String
                    self.refreshToken = accessTokenDict["refresh_token"] as? String
                    
                    #if DEBUG
                        print(accessTokenDict)
                        print("[\(#function)] Access token is \(self.accessToken)")
                        print("[\(#function)] Refresh token is \(self.refreshToken)")
                    #endif
                    
                    // Save expiration date
                    guard let timeInterval = accessTokenDict["expires_in"] as? NSNumber else {
                        completionHandler(success: false)
                        return
                    }
                    let expiresDate = NSDate(timeIntervalSinceNow: timeInterval.doubleValue)
                    
                    NSUserDefaults.standardUserDefaults().setObject(expiresDate, forKey: "accessTokenExpirationDate")
                    NSUserDefaults.standardUserDefaults().synchronize()
                    
                    completionHandler(success: true)
                    
                    // Post notification
//                    NSOperationQueue.mainQueue().addOperationWithBlock({ () -> Void in
//                        NSNotificationCenter.defaultCenter().postNotificationName("signedInToTrakt", object: nil)
//                    })
                }
            }
            catch let jsonSerializationError as NSError {
                #if DEBUG
                    print("[\(#function)] \(jsonSerializationError)")
                #endif
                
                completionHandler(success: false)
            }
        }.resume()
    }
}
