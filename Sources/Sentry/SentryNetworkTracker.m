#import "SentryNetworkTracker.h"
#import "SentryBaggage.h"
#import "SentryBreadcrumb.h"
#import "SentryClient+Private.h"
#import "SentryEvent.h"
#import "SentryException.h"
#import "SentryHub+Private.h"
#import "SentryLog.h"
#import "SentryMechanism.h"
#import "SentryRequest.h"
#import "SentrySDK+Private.h"
#import "SentryScope+Private.h"
#import "SentrySerialization.h"
#import "SentryStacktrace.h"
#import "SentryHttpStatusCodeRange.h"
#import "SentryThread.h"
#import "SentryThreadInspector.h"
#import "SentryTraceContext.h"
#import "SentryTraceHeader.h"
#import "SentryTracer.h"
#import <objc/runtime.h>

@interface
SentryNetworkTracker ()

@property (nonatomic, assign) BOOL isNetworkTrackingEnabled;
@property (nonatomic, assign) BOOL isNetworkBreadcrumbEnabled;
@property (nonatomic, assign) BOOL isCaptureFailedRequests;

@end

@implementation SentryNetworkTracker

+ (SentryNetworkTracker *)sharedInstance
{
    static SentryNetworkTracker *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init
{
    if (self = [super init]) {
        _isNetworkTrackingEnabled = NO;
        _isNetworkBreadcrumbEnabled = NO;
        _isCaptureFailedRequests = NO;
    }
    return self;
}

- (void)enableNetworkTracking
{
    @synchronized(self) {
        _isNetworkTrackingEnabled = YES;
    }
}

- (void)enableNetworkBreadcrumbs
{
    @synchronized(self) {
        _isNetworkBreadcrumbEnabled = YES;
    }
}

- (void)enableCaptureFailedRequests
{
    @synchronized(self) {
        _isCaptureFailedRequests = YES;
    }
}

- (void)disable
{
    @synchronized(self) {
        _isNetworkBreadcrumbEnabled = NO;
        _isNetworkTrackingEnabled = NO;
        _isCaptureFailedRequests = NO;
    }
}

- (BOOL)isTargetMatch:(NSURL *)URL withTargets:(NSArray *)targets
{
    for (id targetCheck in targets) {
        if ([targetCheck isKindOfClass:[NSRegularExpression class]]) {
            NSString *string = URL.absoluteString;
            NSUInteger numberOfMatches =
                [targetCheck numberOfMatchesInString:string
                                             options:0
                                               range:NSMakeRange(0, [string length])];
            if (numberOfMatches > 0) {
                return YES;
            }
        } else if ([targetCheck isKindOfClass:[NSString class]]) {
            if ([URL.absoluteString containsString:targetCheck]) {
                return YES;
            }
        }
    }

    return NO;
}

- (void)urlSessionTaskResume:(NSURLSessionTask *)sessionTask
{
    @synchronized(self) {
        if (!self.isNetworkTrackingEnabled) {
            return;
        }
    }

    if (![self isTaskSupported:sessionTask])
        return;

    // SDK not enabled no need to continue
    if (SentrySDK.options == nil) {
        return;
    }

    NSURL *url = [[sessionTask currentRequest] URL];

    if (url == nil) {
        return;
    }

    // Don't measure requests to Sentry's backend
    NSURL *apiUrl = [NSURL URLWithString:SentrySDK.options.dsn];
    if ([url.host isEqualToString:apiUrl.host] && [url.path containsString:apiUrl.path]) {
        return;
    }

    @synchronized(sessionTask) {
        if (sessionTask.state == NSURLSessionTaskStateCompleted
            || sessionTask.state == NSURLSessionTaskStateCanceling) {
            return;
        }

        __block id<SentrySpan> span;
        __block id<SentrySpan> netSpan;
        netSpan = objc_getAssociatedObject(sessionTask, &SENTRY_NETWORK_REQUEST_TRACKER_SPAN);

        // The task already has a span. Nothing to do.
        if (netSpan != nil) {
            return;
        }

        [SentrySDK.currentHub.scope useSpan:^(id<SentrySpan> _Nullable innerSpan) {
            if (innerSpan != nil) {
                span = innerSpan;
                netSpan = [span
                    startChildWithOperation:SENTRY_NETWORK_REQUEST_OPERATION
                                description:[NSString stringWithFormat:@"%@ %@",
                                                      sessionTask.currentRequest.HTTPMethod, url]];
            }
        }];

        // We only create a span if there is a transaction in the scope,
        // otherwise we have nothing else to do here.
        if (netSpan == nil) {
            SENTRY_LOG_DEBUG(@"No transaction bound to scope. Won't track network operation.");
            return;
        }

        if ([sessionTask currentRequest] &&
            [self isTargetMatch:sessionTask.currentRequest.URL withTargets:SentrySDK.options.tracePropagationTargets]) {
            NSString *baggageHeader = @"";

            SentryTracer *tracer = [SentryTracer getTracer:span];
            if (tracer != nil) {
                baggageHeader = [[tracer.traceContext toBaggage]
                    toHTTPHeaderWithOriginalBaggage:
                        [SentrySerialization
                            decodeBaggage:sessionTask.currentRequest
                                              .allHTTPHeaderFields[SENTRY_BAGGAGE_HEADER]]];
            }

            // First we check if the current request is mutable, so we could easily add a new
            // header. Otherwise we try to change the current request for a new one with the extra
            // header.
            if ([sessionTask.currentRequest isKindOfClass:[NSMutableURLRequest class]]) {
                NSMutableURLRequest *currentRequest
                    = (NSMutableURLRequest *)sessionTask.currentRequest;
                [currentRequest setValue:[netSpan toTraceHeader].value
                      forHTTPHeaderField:SENTRY_TRACE_HEADER];

                if (baggageHeader.length > 0) {
                    [currentRequest setValue:baggageHeader
                          forHTTPHeaderField:SENTRY_BAGGAGE_HEADER];
                }
            } else {
                // Even though NSURLSessionTask doesn't have 'setCurrentRequest', some subclasses
                // do. For those subclasses we replace the currentRequest with a mutable one with
                // the additional trace header. Since NSURLSessionTask is a public class and can be
                // override, we believe this is not considered a private api.
                SEL setCurrentRequestSelector = NSSelectorFromString(@"setCurrentRequest:");
                if ([sessionTask respondsToSelector:setCurrentRequestSelector]) {
                    NSMutableURLRequest *newRequest = [sessionTask.currentRequest mutableCopy];

                    [newRequest setValue:[netSpan toTraceHeader].value
                        forHTTPHeaderField:SENTRY_TRACE_HEADER];

                    if (baggageHeader.length > 0) {
                        [newRequest setValue:baggageHeader
                            forHTTPHeaderField:SENTRY_BAGGAGE_HEADER];
                    }

                    void (*func)(id, SEL, id param)
                        = (void *)[sessionTask methodForSelector:setCurrentRequestSelector];
                    func(sessionTask, setCurrentRequestSelector, newRequest);
                }
            }
        } else {
            SENTRY_LOG_DEBUG(@"Not adding trace_id and baggage headers for %@",
                sessionTask.currentRequest.URL.absoluteString);
        }

        SENTRY_LOG_DEBUG(
            @"SentryNetworkTracker automatically started HTTP span for sessionTask: %@",
            netSpan.description);

        objc_setAssociatedObject(sessionTask, &SENTRY_NETWORK_REQUEST_TRACKER_SPAN, netSpan,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

- (void)urlSessionTask:(NSURLSessionTask *)sessionTask setState:(NSURLSessionTaskState)newState
{
    // TODO: Can I actually read isCaptureFailedRequests directly from the options?
    // Why do we have them here and in the options?
    if (!self.isNetworkTrackingEnabled && !self.isNetworkBreadcrumbEnabled
        && !self.isCaptureFailedRequests) {
        return;
    }

    if (![self isTaskSupported:sessionTask]) {
        return;
    }

    if (newState == NSURLSessionTaskStateRunning) {
        return;
    }

    NSURL *url = [[sessionTask currentRequest] URL];

    if (url == nil) {
        return;
    }

    // Don't measure requests to Sentry's backend
    NSURL *apiUrl = [NSURL URLWithString:SentrySDK.options.dsn];
    if ([url.host isEqualToString:apiUrl.host] && [url.path containsString:apiUrl.path]) {
        return;
    }

    id<SentrySpan> netSpan;
    @synchronized(sessionTask) {
        netSpan = objc_getAssociatedObject(sessionTask, &SENTRY_NETWORK_REQUEST_TRACKER_SPAN);
        // We'll just go through once
        objc_setAssociatedObject(sessionTask, &SENTRY_NETWORK_REQUEST_TRACKER_SPAN, nil,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (sessionTask.state == NSURLSessionTaskStateRunning) {
        [self captureEvent:sessionTask];

        [self addBreadcrumbForSessionTask:sessionTask];

        NSInteger responseStatusCode = [self urlResponseStatusCode:sessionTask.response];

        if (responseStatusCode != -1) {
            NSNumber *statusCode = [NSNumber numberWithInteger:responseStatusCode];

            if (netSpan != nil) {
                [netSpan setTagValue:[NSString stringWithFormat:@"%@", statusCode]
                              forKey:@"http.status_code"];
            }
        }
    }

    if (netSpan == nil) {
        return;
    }

    [netSpan setDataValue:sessionTask.currentRequest.HTTPMethod forKey:@"method"];
    [netSpan setDataValue:sessionTask.currentRequest.URL.path forKey:@"url"];
    [netSpan setDataValue:@"fetch" forKey:@"type"];

    [netSpan finishWithStatus:[self statusForSessionTask:sessionTask state:newState]];
    SENTRY_LOG_DEBUG(@"SentryNetworkTracker finished HTTP span for sessionTask");
}

- (void)captureEvent:(NSURLSessionTask *)sessionTask
{
    NSHTTPURLResponse *myResponse = (NSHTTPURLResponse *)sessionTask.response;
    NSNumber *responseStatusCode = [NSNumber numberWithLongLong:myResponse.statusCode];

    if (!self.isCaptureFailedRequests || ![self containsStatusCode:myResponse.statusCode]) {
        return;
    }
    
    if (![self isTargetMatch:sessionTask.currentRequest.URL withTargets:SentrySDK.options.failedRequestTargets]) {
        return;
    }
    
    NSString *message = [NSString
        stringWithFormat:@"HTTP Client Error with status code: %ld", (long)myResponse.statusCode];

    SentryEvent *event = [[SentryEvent alloc] initWithLevel:kSentryLevelError];

    SentryThreadInspector *threadInspector = SentrySDK.currentHub.getClient.threadInspector;
    // TODO: getCurrentThreads does not return stack traces
    NSArray<SentryThread *> *threads = [threadInspector getCurrentThreadsWithStackTrace];

    SentryException *sentryException = [[SentryException alloc] initWithValue:message
                                                                         type:@"HTTP-ClientError"];
    sentryException.mechanism =
        [[SentryMechanism alloc] initWithType:@"SentryNetworkTrackingIntegration"];

    if (threads.count > 0) {
        SentryStacktrace *sentryStacktrace = [threads[0] stacktrace];
        sentryStacktrace.snapshot = @(YES);

        sentryException.stacktrace = sentryStacktrace;
        // TODO: do I need this?
        //    [threads enumerateObjectsUsingBlock:^(SentryThread *_Nonnull obj, NSUInteger idx,
        //        BOOL *_Nonnull stop) { obj.current = [NSNumber numberWithBool:idx == 0]; }];
    }

    SentryRequest *request = [[SentryRequest alloc] init];

    NSURLRequest *myRequest = (NSURLRequest *)sessionTask.currentRequest;

    // TODO: strip query string and fragment from url
    NSURL *url = [[sessionTask currentRequest] URL];
    request.url = url.absoluteString;

    request.fragment = url.fragment;
    request.queryString = url.query;
    request.method = myRequest.HTTPMethod;
    if (sessionTask.countOfBytesSent != 0) {
        request.bodySize = [NSNumber numberWithLongLong:sessionTask.countOfBytesSent];
    }
    if (nil != myRequest.allHTTPHeaderFields) {
        NSDictionary<NSString *, NSString *> *headers = myRequest.allHTTPHeaderFields.copy;
        request.headers = headers;
        request.cookies = headers[@"Cookie"];
    }

    event.exceptions = @[ sentryException ];
    event.request = request;

    NSMutableDictionary<NSString *, id> *context = [[NSMutableDictionary alloc] init];
    ;
    NSMutableDictionary<NSString *, id> *response = [[NSMutableDictionary alloc] init];

    [response setValue:responseStatusCode forKey:@"status_code"];
    if (nil != myResponse.allHeaderFields) {
        NSDictionary<NSString *, NSString *> *headers = myResponse.allHeaderFields.copy;
        [response setValue:headers forKey:@"headers"];
        [response setValue:headers[@"Cookie"] forKey:@"cookies"];
    }
    if (sessionTask.countOfBytesReceived != 0) {
        [response setValue:[NSNumber numberWithLongLong:sessionTask.countOfBytesReceived]
                    forKey:@"body_size"];
    }

    context[@"response"] = response;
    event.context = context;

    [SentrySDK captureEvent:event];
}

- (BOOL)containsStatusCode:(NSInteger)statusCode {
    for (SentryHttpStatusCodeRange *range in SentrySDK.options.failedRequestStatusCodes) {
        if ([range isInRange:statusCode]) {
            return YES;
        }
    }
    
    return NO;
}

- (void)addBreadcrumbForSessionTask:(NSURLSessionTask *)sessionTask
{
    if (!self.isNetworkBreadcrumbEnabled) {
        return;
    }

    SentryLevel breadcrumbLevel = sessionTask.error != nil ? kSentryLevelError : kSentryLevelInfo;
    SentryBreadcrumb *breadcrumb = [[SentryBreadcrumb alloc] initWithLevel:breadcrumbLevel
                                                                  category:@"http"];
    breadcrumb.type = @"http";
    NSMutableDictionary<NSString *, id> *breadcrumbData = [NSMutableDictionary new];
    breadcrumbData[@"url"] = sessionTask.currentRequest.URL.absoluteString;
    breadcrumbData[@"method"] = sessionTask.currentRequest.HTTPMethod;
    breadcrumbData[@"request_body_size"] =
        [NSNumber numberWithLongLong:sessionTask.countOfBytesSent];
    breadcrumbData[@"response_body_size"] =
        [NSNumber numberWithLongLong:sessionTask.countOfBytesReceived];

    NSInteger responseStatusCode = [self urlResponseStatusCode:sessionTask.response];

    if (responseStatusCode != -1) {
        NSNumber *statusCode = [NSNumber numberWithInteger:responseStatusCode];
        breadcrumbData[@"status_code"] = statusCode;
        breadcrumbData[@"reason"] =
            [NSHTTPURLResponse localizedStringForStatusCode:responseStatusCode];
    }

    breadcrumb.data = breadcrumbData;
    [SentrySDK addBreadcrumb:breadcrumb];
}

- (NSInteger)urlResponseStatusCode:(NSURLResponse *)response
{
    if (response != nil && [response isKindOfClass:[NSHTTPURLResponse class]]) {
        return ((NSHTTPURLResponse *)response).statusCode;
    }
    return -1;
}

- (SentrySpanStatus)statusForSessionTask:(NSURLSessionTask *)task state:(NSURLSessionTaskState)state
{
    switch (state) {
    case NSURLSessionTaskStateSuspended:
        return kSentrySpanStatusAborted;
    case NSURLSessionTaskStateCanceling:
        return kSentrySpanStatusCancelled;
    case NSURLSessionTaskStateCompleted:
        return task.error != nil
            ? kSentrySpanStatusUnknownError
            : [self spanStatusForHttpResponseStatusCode:[self urlResponseStatusCode:task.response]];
    case NSURLSessionTaskStateRunning:
        break;
    }
    return kSentrySpanStatusUndefined;
}

- (BOOL)isTaskSupported:(NSURLSessionTask *)task
{
    // Since streams are usually created to stay connected we don't measure this type of data
    // transfer.
    return [task isKindOfClass:[NSURLSessionDataTask class]] ||
        [task isKindOfClass:[NSURLSessionDownloadTask class]] ||
        [task isKindOfClass:[NSURLSessionUploadTask class]];
}

// https://develop.sentry.dev/sdk/event-payloads/span/
- (SentrySpanStatus)spanStatusForHttpResponseStatusCode:(NSInteger)statusCode
{
    if (statusCode >= 200 && statusCode < 300) {
        return kSentrySpanStatusOk;
    }

    switch (statusCode) {
    case 400:
        return kSentrySpanStatusInvalidArgument;
    case 401:
        return kSentrySpanStatusUnauthenticated;
    case 403:
        return kSentrySpanStatusPermissionDenied;
    case 404:
        return kSentrySpanStatusNotFound;
    case 409:
        return kSentrySpanStatusAborted;
    case 429:
        return kSentrySpanStatusResourceExhausted;
    case 500:
        return kSentrySpanStatusInternalError;
    case 501:
        return kSentrySpanStatusUnimplemented;
    case 503:
        return kSentrySpanStatusUnavailable;
    case 504:
        return kSentrySpanStatusDeadlineExceeded;
    }
    return kSentrySpanStatusUndefined;
}

@end
