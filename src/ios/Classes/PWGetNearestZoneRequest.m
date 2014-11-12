//
//  PWGetNearestZoneRequest.m
//  Pushwoosh SDK
//  (c) Pushwoosh 2012
//

#import "PWGetNearestZoneRequest.h"

#if ! __has_feature(objc_arc)
#error "ARC is required to compile Pushwoosh SDK"
#endif

@implementation PWGetNearestZoneRequest

- (NSString *) methodName {
	return @"getNearestZone";
}

- (NSDictionary *) requestDictionary {
	NSMutableDictionary *dict = [self baseDictionary];
	
	[dict setObject:[NSNumber numberWithDouble:_userCoordinate.latitude] forKey:@"lat"];
	[dict setObject:[NSNumber numberWithDouble:_userCoordinate.longitude] forKey:@"lng"];
	
	return dict;
}

- (void)parseResponse:(NSDictionary *)response {
	if (response && [response isKindOfClass:[NSDictionary class]]) {
		NSNumber *distance = [response objectForKey:@"distance"];
		NSNumber *lat = [response objectForKey:@"lat"];
		NSNumber *lng = [response objectForKey:@"lng"];
		NSNumber *radius = [response objectForKey:@"range"];
		NSString *name  = [response objectForKey:@"name"];
		
		if (distance && [distance isKindOfClass:[NSNumber class]] &&
			lat && [lat isKindOfClass:[NSNumber class]] &&
			lng && [lng isKindOfClass:[NSNumber class]]) {
			CLLocationDistance properRadius = 100;
			
			if (radius) {
				properRadius = [radius doubleValue];
			}
		
			if (!name) {
				name = @"Unknown";
			}
		
			self.nearestGeozone = [PWGeozone geozoneWithCenter:CLLocationCoordinate2DMake([lat doubleValue], [lng doubleValue]) radius:properRadius distance:[distance doubleValue] name:name];
		}
	}
}

@end
