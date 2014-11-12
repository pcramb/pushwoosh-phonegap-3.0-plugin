//
//  PWGetBeaconsRequest
//  Pushwoosh SDK
//  (c) Pushwoosh 2014
//

#import "PWGetBeaconsRequest.h"

@implementation PWGetBeaconsRequest

- (NSString *) methodName {
	return @"getApplicationBeacons";
}

- (NSDictionary *) requestDictionary {
	NSMutableDictionary *dict = [self baseDictionary];
	return dict;
}

- (void)parseResponse:(NSDictionary *)response {
	self.uuid = [response objectForKey:@"uuid"];
	self.indoorOffset = [[response objectForKey:@"indoor_offset"] doubleValue];
}

@end
