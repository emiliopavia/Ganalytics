//
//  Ganalytics.h
//  Ganalytics
//
//  Created by Emilio Pavia on 11/12/14.
//  Copyright (c) 2014 Emilio Pavia. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface Ganalytics : NSObject

@property (nonatomic, strong) NSString *trackingID;

@property (nonatomic, assign) BOOL useSSL;      // YES by default
@property (nonatomic, assign) BOOL debugMode;   // NO by deafult

+ (instancetype)sharedInstance;

- (instancetype)initWithTrackingID:(NSString *)trackingID NS_DESIGNATED_INITIALIZER;

- (void)sendEventWithCategory:(NSString *)category  // required
                       action:(NSString *)action    // required
                        label:(NSString *)label     // optional
                        value:(NSNumber *)value;    // optional

- (void)sendSocialWithNetwork:(NSString *)network   // required
                       action:(NSString *)action    // required
                       target:(NSString *)target;   // optional

- (void)sendTimingWithCategory:(NSString *)category // required
                      interval:(NSNumber *)interval // required (milliseconds)
                          name:(NSString *)name     // optional
                         label:(NSString *)label;   // optional

- (void)setCustomDimensionAtIndex:(NSInteger)index  // between 1 and 200 (inclusive)
                            value:(NSString *)value;

- (void)setCustomMetricAtIndex:(NSInteger)index     // between 1 and 200 (inclusive)
                         value:(NSInteger)value;

@end
