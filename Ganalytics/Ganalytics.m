//
//  Ganalytics.m
//  Ganalytics
//
//  Created by Emilio Pavia on 11/12/14.
//  Copyright (c) 2014 Emilio Pavia. All rights reserved.
//

#import "Ganalytics.h"

#ifdef NDEBUG
    #define GANLog(...)
#else
    #define GANLog NSLog
#endif

#define MAX_PAYLOAD_LENGTH 8192
#define RETRY_INTERVAL 20   // in seconds

@interface Ganalytics () <NSURLSessionDelegate>

@property (nonatomic, strong, readwrite) NSString *clientID;
@property (nonatomic, strong, readwrite) NSString *userAgent;

@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong) NSDictionary *defaultParameters;
@property (nonatomic, strong) NSMutableDictionary *customDimensions;
@property (nonatomic, strong) NSMutableDictionary *customMetrics;
@property (nonatomic, strong) NSMutableDictionary *overrideParameters;

@end

@interface NSDictionary (Ganalytics)

- (NSString *)gan_queryString;

@end

@implementation Ganalytics

+ (instancetype)sharedInstance {
    static Ganalytics *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[Ganalytics alloc] init];
    });
    return sharedInstance;
}

- (instancetype)initWithTrackingID:(NSString *)trackingID {
    self = [super init];
    if (self) {
        self.trackingID = trackingID;
        self.useSSL = YES;
        self.debugMode = NO;
        
        UIDevice *currentDevice = [UIDevice currentDevice];
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
        self.clientID = currentDevice.identifierForVendor.UUIDString;
        self.userAgent = [NSString stringWithFormat:@"%@/%@ (%@; CPU OS %@ like Mac OS X)",
                          infoDictionary[@"CFBundleName"],
                          infoDictionary[@"CFBundleShortVersionString"],
                          currentDevice.model,
                          currentDevice.systemVersion];
        
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        self.session = [NSURLSession sessionWithConfiguration:configuration
                                                     delegate:nil
                                                delegateQueue:nil];
        
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        CGFloat screenScale = [UIScreen mainScreen].scale;
        self.defaultParameters = @{ @"v" : @1,
                                    @"cid" : self.clientID,
                                    @"aid" : infoDictionary[@"CFBundleIdentifier"],
                                    @"an" : infoDictionary[@"CFBundleName"],
                                    @"av" : infoDictionary[@"CFBundleShortVersionString"],
                                    @"ul" : [NSLocale preferredLanguages].firstObject,
                                    @"sr" : [NSString stringWithFormat:@"%.0fx%.0f@%.fx", CGRectGetWidth(screenBounds), CGRectGetHeight(screenBounds), screenScale]};
        
        self.customDimensions = [NSMutableDictionary dictionary];
        self.customMetrics = [NSMutableDictionary dictionary];
        self.overrideParameters = [NSMutableDictionary dictionary];
    }
    return self;
}

- (instancetype)init {
    return [self initWithTrackingID:nil];
}

- (void)sendEventWithCategory:(NSString *)category
                       action:(NSString *)action
                        label:(NSString *)label
                        value:(NSNumber *)value {
    NSParameterAssert(category);
    NSParameterAssert(action);
    
    NSMutableDictionary *parameters = @{ @"t" : @"event",
                                         @"ec" : category,
                                         @"ea" : action }.mutableCopy;
    if (label) {
        parameters[@"el"] = label;
    }
    if (value) {
        parameters[@"ev"] = value;
    }
    
    [self sendRequestWithParameters:parameters];
}

- (void)sendSocialWithNetwork:(NSString *)network
                       action:(NSString *)action
                       target:(NSString *)target {
    NSParameterAssert(network);
    NSParameterAssert(action);
    
    NSMutableDictionary *parameters = @{ @"t" : @"social",
                                         @"sn" : network,
                                         @"sa" : action }.mutableCopy;
    if (target) {
        parameters[@"st"] = target;
    }
    
    [self sendRequestWithParameters:parameters];
}

- (void)sendTimingWithCategory:(NSString *)category
                      interval:(NSNumber *)interval
                          name:(NSString *)name
                         label:(NSString *)label {
    NSParameterAssert(category);
    NSParameterAssert(interval);
    
    NSMutableDictionary *parameters = @{ @"t" : @"timing",
                                         @"utc" : category,
                                         @"utt" : interval }.mutableCopy;
    if (name) {
        parameters[@"utv"] = name;
    }
    if (label) {
        parameters[@"utl"] = label;
    }
    
    [self sendRequestWithParameters:parameters];
}

- (void)sendRequestWithParameters:(NSDictionary *)parameters date:(NSDate *)date {
    NSParameterAssert(date);
    NSAssert(self.trackingID, @"trackingID cannot be nil");
    
    NSMutableDictionary *params = self.defaultParameters.mutableCopy;
    [params addEntriesFromDictionary:self.overrideParameters];
    [params setObject:self.trackingID forKey:@"tid"];
    [params addEntriesFromDictionary:self.customDimensions];
    [params addEntriesFromDictionary:self.customMetrics];
    [params addEntriesFromDictionary:parameters];
    [params addEntriesFromDictionary:@{ @"qt" : [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSinceDate:date] * 1000.0] }];
    
    NSURLRequest *request = [self requestWithParameters:params];
    if (request.HTTPBody.length > MAX_PAYLOAD_LENGTH) {
        GANLog(@"[%@] The body must be no longer than %d bytes.", NSStringFromClass([self class]), MAX_PAYLOAD_LENGTH);
    }
    
    GANLog(@"[%@] %@ %@ %@ DEBUG = %@", NSStringFromClass([self class]), request.HTTPMethod, request.URL, params, (self.debugMode ? @"YES" : @"NO"));
    
    if (!self.debugMode) {
        [[self.session dataTaskWithRequest:[self requestWithParameters:params]
                         completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                             if (error) {
                                 dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(RETRY_INTERVAL * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                     [self sendRequestWithParameters:parameters date:date];
                                 });
                             }
                         }] resume];
    }
}

- (void)sendRequestWithParameters:(NSDictionary *)parameters {
    [self sendRequestWithParameters:parameters date:[NSDate date]];
}

- (void)sendView:(NSString *)screenName {
    NSParameterAssert(screenName);
    
    NSMutableDictionary *parameters = @{ @"t" : @"screenview",
                                         @"cd" : screenName }.mutableCopy;
    
    [self sendRequestWithParameters:parameters];

}

- (void)setCustomDimensionAtIndex:(NSInteger)index
                            value:(NSString *)value {
    NSParameterAssert(value);
    
    if (index < 1 || index > 200) {
        GANLog(@"[%@] The index for custom dimensions must be between 1 and 200 (inclusive).", NSStringFromClass([self class]));
    } else {
        NSString *key = [NSString stringWithFormat:@"cd%ld", (long)index];
        self.customDimensions[key] = value;
    }
}

- (void)setCustomMetricAtIndex:(NSInteger)index
                         value:(NSInteger)value {
    if (index < 1 || index > 200) {
        GANLog(@"[%@] The index for custom metrics must be between 1 and 200 (inclusive).", NSStringFromClass([self class]));
    } else {
        NSString *key = [NSString stringWithFormat:@"cm%ld", (long)index];
        self.customMetrics[key] = [NSString stringWithFormat:@"%ld", (long)value];
    }
}

- (void)setValue:(id)value forDefaultParameter:(GANDefaultParameter)parameter {
    NSString *key = nil;
    switch (parameter) {
        case GANApplicationID:
            key = @"aid";
            break;
        case GANApplicationName:
            key = @"an";
            break;
        case GANApplicationVersion:
            key = @"av";
            break;
        default:
            break;
    }
    
    if (key) {
        if (value) {
            self.overrideParameters[key] = value;
        } else {
            [self.overrideParameters removeObjectForKey:key];
        }
    }
}

- (NSURL *)endpointURL {
    if (self.useSSL) {
        return [NSURL URLWithString:@"https://ssl.google-analytics.com/collect"];
    }
    return [NSURL URLWithString:@"http://www.google-analytics.com/collect"];
}

- (NSURLRequest *)requestWithParameters:(NSDictionary *)parameters {
    NSString *queryString = [parameters gan_queryString];
    NSData *payload = [NSData dataWithBytes:[queryString UTF8String] length:strlen([queryString UTF8String])];
    
    NSMutableURLRequest *postRequest = [NSMutableURLRequest requestWithURL:self.endpointURL];
    [postRequest setValue:self.userAgent forHTTPHeaderField:@"User-Agent"];
    [postRequest setHTTPMethod:@"POST"];
    [postRequest setHTTPBody:payload];

    return postRequest;
}

@end

@implementation NSDictionary (Ganalytics)

- (NSString *)gan_queryString {
    NSMutableArray *parameters = [NSMutableArray array];
    for (id key in self) {
        id value = [self objectForKey:key];
        NSString *parameter = [[NSString stringWithFormat: @"%@=%@", key, value] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        [parameters addObject:parameter];
    }
    return [parameters componentsJoinedByString:@"&"];
}

@end