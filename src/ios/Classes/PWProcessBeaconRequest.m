//
//  PWProcessBeaconRequest
//  Pushwoosh SDK
//  (c) Pushwoosh 2014
//

#import "PWProcessBeaconRequest.h"

@implementation PWProcessBeaconRequest

- (NSMutableDictionary *)requestDictionary {
    NSMutableDictionary *dict = [self baseDictionary];
    
    [dict setObject:_uuid forKey:@"uuid"];
    [dict setObject:_major forKey:@"major_number"];
    [dict setObject:_minor forKey:@"minor_number"];
    [dict setObject:[self stringForAction:_action] forKey:@"action"];
    
    return dict;
}

- (NSString *)stringForAction:(PWBeaconAction)action {
    switch (action) {
        case PWBeaconActionCame:
            return @"came";
        case PWBeaconActionIndoor:
            return @"indoor";
        case PWBeaconActionCameOut:
            return @"cameout";
        default:
            return @"unknown";
    }
}

- (NSString *)methodName {
	return @"processBeacon";
}

@end
