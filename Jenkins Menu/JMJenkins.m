/**
 * Jenkins Menu
 * https://github.com/qvacua/jenkins-menu
 * http://qvacua.com
 *
 * See LICENSE
 */

#import "JMJenkins.h"
#import "JMJenkinsJob.h"
#import "JMJenkinsDelegate.h"
#import "JMTrustedHostManager.h"
#import "JMLog.h"
#import "JMKeychainManager.h"
#import "AFHTTPClient.h"

static NSTimeInterval const qDefaultInterval = 5 * 60;
static const NSTimeInterval qTimeoutInterval = 15;
static NSString *const qJenkinsXmlApiPath = @"/api/xml";

@interface JMJenkins ()

@property NSURLConnection *connection;
@property(readwrite) NSInteger lastHttpStatusCode;
@property(readwrite) NSInteger connectionState;
@property(readwrite) NSURL *viewUrl;
@property(readonly) NSMutableArray *mutableJobs;
@property(readonly) NSMutableArray *filteredJobs;
@property(readwrite) NSString *potentialHostToTrust;

@end

@implementation JMJenkins {
    NSURL *_url;
}

@dynamic allJobs;
@dynamic jobs;
@dynamic url;

#pragma mark Properties
- (NSArray *)allJobs {
    return self.mutableJobs;
}

- (NSArray *)jobs {
    return self.filteredJobs;
}

- (NSURL *)url {
    return _url;
}

- (void)setUrl:(NSURL *)newUrl {
    _url = newUrl;
    _xmlUrl = [newUrl URLByAppendingPathComponent:qJenkinsXmlApiPath];
}

#pragma mark Public
- (void)update {
    [self.connection cancel];

    if (self.secured && self.credential == nil) {
        self.connectionState = JMJenkinsConnectionStateNoCredential;
        [self.delegate jenkins:self wrongCredential:nil];

        return;
    }

    NSURLRequest *request = [self urlRequest];
    self.connection = [[NSURLConnection alloc] initWithRequest:request delegate:self];
    log4Info(@"Connecting to %@", self.xmlUrl);

    [self.delegate jenkins:self updateStarted:nil];

    if (self.connection == nil) {
        log4Warn(@"Connection to %@ failed!", self.xmlUrl);

        self.connectionState = JMJenkinsConnectionStateConnectionFailure;
        [self.delegate jenkins:self updateFailed:nil];
    }
}

- (NSUInteger)countOfRedJobs {
    return [self countState:JMJenkinsJobStateRed];
}

- (NSUInteger)countOfYellowJobs {
    return [self countState:JMJenkinsJobStateYellow];
}

- (NSUInteger)countOfGreenJobs {
    return [self countState:JMJenkinsJobStateGreen];
}

- (JMJenkinsJobsTotalState)totalState {
    if ([self countOfRedJobs] > 0) {
        return JMJenkinsTotalStateRed;
    }

    if ([self countOfYellowJobs] > 0) {
        return JMJenkinsTotalStateYellow;
    }

    if ([self countOfGreenJobs] > 0) {
        return JMJenkinsTotalStateGreen;
    }

    return JMJenkinsTotalStateUnknown;
}

#pragma mark NSObject
- (id)init {
    self = [super init];
    if (self) {
        _interval = qDefaultInterval;
        _connectionState = JMJenkinsConnectionStateUnknown;
        _lastHttpStatusCode = qHttpStatusUnknown;
        _mutableJobs = [[NSMutableArray alloc] init];
        _filteredJobs = [[NSMutableArray alloc] init];
        _blacklistItems = [[NSArray alloc] init];
        _blacklistItemsFilter = JMJenkinsJobFilterIgnore;
    }

    return self;
}

#pragma mark NSURLConnectionDataDelegate
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    log4Debug(@"response");
    NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;

    NSInteger responseStatusCode = [httpResponse statusCode];
    self.lastHttpStatusCode = responseStatusCode;

    /**
    * Forbidden occurs when the Jenkins is secured. Jenkins does not send a authentication challenge,
    * instead it responses with Forbidden and a login form. This means the -connection:didReceiveData: gets invoked.
    */
    if (responseStatusCode == qHttpForbidden) {
        self.connectionState = JMJenkinsConnectionStateForbidden;

        return;
    }

    /**
    * Unauthorized occurs when the credential is wrong.
    */
    if (responseStatusCode == qHttpUnauthorized) {
        self.connectionState = JMJenkinsConnectionStateWrongCredential;

        return;
    }

    if (responseStatusCode < qHttpStatusOk || responseStatusCode >= qHttpStatusBadRequest) {
        log4Warn(@"Connection to %@ was not successful. The Http status code was: %ld", self.xmlUrl, responseStatusCode);

        self.connectionState = JMJenkinsConnectionStateHttpFailure;
        [self.delegate jenkins:self updateFailed:@{
                qJenkinsHttpResponseErrorKey : @(responseStatusCode)
        }];

        return;
    }

    self.connectionState = JMJenkinsConnectionStateSuccessful;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    log4Debug(@"data");

    if (self.connectionState == JMJenkinsConnectionStateForbidden) {
        log4Debug(@"forbidden");
        self.secured = YES;
        [self.delegate jenkins:self forbidden:nil];
        return;
    }

    if (self.connectionState == JMJenkinsConnectionStateWrongCredential) {
        log4Debug(@"wrong credential");
        [self.delegate jenkins:self wrongCredential:nil];
        return;
    }

    if (self.connectionState != JMJenkinsConnectionStateSuccessful) {
        return;
    }

    NSXMLDocument *xmlDoc = [self xmlDocumentFromData:data];
    if (xmlDoc == nil) {
        self.connectionState = JMJenkinsConnectionStateXmlFailure;
        return;
    }

    NSArray *children = [[xmlDoc rootElement] children];
    if ([children count] == 0) {
        log4Warn(@"XML of %@ is empty.", self.xmlUrl);

        self.connectionState = JMJenkinsConnectionStateXmlFailure;
        return;
    }

    [self.mutableJobs removeAllObjects];
    [self.filteredJobs removeAllObjects];

    [children enumerateObjectsUsingBlock:^(NSXMLNode *childNode, NSUInteger index, BOOL *stop) {
        if ([[childNode name] isEqualToString:@"primaryView"]) {
            self.viewUrl = [self viewUrlFromXmlNode:childNode];
            return;
        }

        if ([[childNode name] isEqualToString:@"job"]) {
            JMJenkinsJob *job = [self jobsFromXmlNode:childNode];
            [self.mutableJobs addObject:job];
            if (self.blacklistItemsFilter == JMJenkinsJobFilterIgnore && ![self.blacklistItems containsObject:job.name]) {
                [self.filteredJobs addObject:job];
            } else if (self.blacklistItemsFilter == JMJenkinsJobFilterInclude && [self.blacklistItems containsObject:job.name]) {
                [self.filteredJobs addObject:job];
            }
            return;
        }
    }];

    [self.delegate jenkins:self updateFinished:nil];
}

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    /**
    * When we get an authentication challenge from the server, this delegate method is called before
    * - connecion:didReceiveResponse:
    * - connecion:didReceiveData:
    */

    log4Debug(@"challenge");
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if ([self.trustedHostManager shouldTrustHost:challenge.protectionSpace.host]) {
            NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            [challenge.sender useCredential:credential forAuthenticationChallenge:challenge];

            self.potentialHostToTrust = nil;

            return;
        }
    }

    self.potentialHostToTrust = challenge.protectionSpace.host;

    if ([challenge.sender respondsToSelector:@selector(performDefaultHandlingForAuthenticationChallenge:)]) {
        [challenge.sender performDefaultHandlingForAuthenticationChallenge:challenge];
        return;
    }

    [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    if ([error code] == NSURLErrorServerCertificateUntrusted) {
        log4Warn(@"Certification issue with %@", self.xmlUrl);
        self.connectionState = JMJenkinsConnectionStateServerTrustFailure;
        [self.delegate jenkins:self serverTrustFailedwithHost:_potentialHostToTrust];

        return;
    }

    log4Warn(@"Connection to %@ failed: %@", self.xmlUrl, connection);
    self.connectionState = JMJenkinsConnectionStateFailure;
    [self.delegate jenkins:self updateFailed:@{
            qJenkinsConnectionErrorKey : error
    }];
}

#pragma mark Private
- (JMJenkinsJob *)jobsFromXmlNode:(NSXMLNode *)node {
    JMJenkinsJob *job = [[JMJenkinsJob alloc] init];

    [[node children] enumerateObjectsUsingBlock:^(id childNode, NSUInteger index, BOOL *stop) {
        NSString *nodeName = [childNode name];
        NSString *nodeStringValue = [childNode stringValue];

        if ([nodeName isEqualToString:@"name"]) {
            job.name = nodeStringValue;
            return;
        }

        if ([nodeName isEqualToString:@"url"]) {
            job.url = [NSURL URLWithString:nodeStringValue];
            return;
        }

        if ([nodeName isEqualToString:@"color"]) {
            job.state = [self jobStateFromColor:nodeStringValue];
            job.running = [self runningStateFromColor:nodeStringValue];
            return;
        }
    }];

    return job;
}

- (NSXMLDocument *)xmlDocumentFromData:(NSData *)xmlData {
    NSError *xmlError = nil;
    NSXMLDocument *xmlDoc = [[NSXMLDocument alloc] initWithData:xmlData options:0 error:&xmlError];

    if (xmlError) {
        log4Warn(@"XML parsing of %@ failed: %@", self.xmlUrl, xmlError);
        return nil;
    }

    return xmlDoc;
}

- (NSURL *)viewUrlFromXmlNode:(NSXMLNode *)node {
    __block NSURL *viewUrl;
    [[node children] enumerateObjectsUsingBlock:^(id childNode, NSUInteger index, BOOL *stop) {
        if (![[childNode name] isEqualToString:@"url"]) {
            return;
        }

        viewUrl = [NSURL URLWithString:[childNode stringValue]];
        *stop = YES;
    }];

    return viewUrl;
}

- (JMJenkinsJobState)jobStateFromColor:(NSString *)color {
    if ([color hasPrefix:@"blue"]) {
        return JMJenkinsJobStateGreen;
    }

    if ([color hasPrefix:@"yellow"]) {
        return JMJenkinsJobStateYellow;
    }

    if ([color hasPrefix:@"red"]) {
        return JMJenkinsJobStateRed;
    }

    if ([color hasPrefix:@"aborted"]) {
        return JMJenkinsJobStateAborted;
    }

    if ([color hasPrefix:@"disabled"]) {
        return JMJenkinsJobStateDisabled;
    }

    return JMJenkinsJobStateUnknown;
}

- (BOOL)runningStateFromColor:(NSString *)color {
    if ([color hasSuffix:@"_anime"]) {
        return YES;
    }

    return NO;
}

- (NSUInteger)countState:(JMJenkinsJobState)jobState {
    NSUInteger count = 0;
    for (JMJenkinsJob *job in self.jobs) {
        if (self.blacklistItemsFilter == JMJenkinsJobFilterIgnore &&
                [self.blacklistItems containsObject:job.name]) {
            continue;
        }
        
        if (self.blacklistItemsFilter == JMJenkinsJobFilterInclude &&
            ![self.blacklistItems containsObject:job.name]) {
            continue;
        }
        
        if (job.state == jobState) {
            count++;
        }
    }

    return count;
}

- (NSURLRequest *)urlRequest {
    NSMutableURLRequest *urlRequest = [NSMutableURLRequest requestWithURL:self.xmlUrl cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:qTimeoutInterval];

    if (self.credential == nil) {
        return urlRequest;
    }

    NSString *username = self.credential.username;
    NSString *password = self.credential.password;

    /**
    * For one https server I could try out the HTTP basic auth method did not work. Thus, we are now using the POST
    * method to get through. We're using AFNetworking for that.
    *
    * It could well be that we have to modify the following code when Jenkins changes the internal login mechanism.
    */
    AFHTTPClient *client = [AFHTTPClient clientWithBaseURL:self.url];
    urlRequest = [client requestWithMethod:@"POST" path:@"j_acegi_security_check" parameters:@{
            @"from" : qJenkinsXmlApiPath,
            @"j_username" : username,
            @"j_password" : password
    }];

    return urlRequest;
}

@end
