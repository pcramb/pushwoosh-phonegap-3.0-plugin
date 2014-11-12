//
//  PWSendPurchaseRequest
//  Pushwoosh SDK
//  (c) Pushwoosh 2014
//

#import "PWSendPurchaseRequest.h"

#if ! __has_feature(objc_arc)
#error "ARC is required to compile Pushwoosh SDK"
#endif

@implementation PWSendPurchaseRequest

- (NSString *) methodName {
	return @"setPurchase";
}

- (NSDictionary *) requestDictionary {
	NSMutableDictionary *dict = [self baseDictionary];
	
	[dict setObject:_productIdentifier forKey:@"productIdentifier"];
	[dict setObject:[NSNumber numberWithInteger:_quantity] forKey:@"quantity"];
	
	if(_transactionDate != nil)
		[dict setObject:[NSNumber numberWithInt: _transactionDate.timeIntervalSince1970] forKey:@"transactionDate"];

	[dict setObject:_price forKey:@"price"];
	[dict setObject:_currencyCode forKey:@"currency"];

	return dict;
}

@end
