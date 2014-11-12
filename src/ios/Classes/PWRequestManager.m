//
//  PWRequestManager.m
//  Pushwoosh SDK
//  (c) Pushwoosh 2012
//

#import "PWRequestManager.h"
#import "PushRuntime.h"
#import "PWSetTagsRequest.h"
#import "Constants.h"

#if ! __has_feature(objc_arc)
#error "ARC is required to compile Pushwoosh SDK"
#endif

@implementation PWRequestManager

static NSMutableArray * requests = nil;
static BOOL threadCreated = NO;

+ (PWRequestManager *) sharedManager {
	static PWRequestManager *instance = nil;
	if (!instance) {
		instance = [[PWRequestManager alloc] init];
	}
	return instance;
}

- (id) init {
	if(self = [super init]) {
		if(!threadCreated) {
			[NSThread detachNewThreadSelector:@selector(myThreadMainMethod) toTarget:self withObject:nil];
			threadCreated = YES;
			requests = [NSMutableArray new];
		}
	}
	
	return self;
}

- (BOOL) sendRequest: (PWRequest *) request {
	return [self sendRequest:request error:nil];
}

- (NSString *) defaultBaseUrl {
	NSString *serviceAddressUrl = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"Pushwoosh_BASEURL"];

	if(!serviceAddressUrl) {
		serviceAddressUrl = kBaseDefaultURL;
	}
	
	return serviceAddressUrl;
}

//This thread polls request queue 1 second, groups the requests in a single one and makes API cal
- (void) myThreadMainMethod {

	while(true) {
		@autoreleasepool {

		sleep(1);

		PWRequest * request = nil;
		NSMutableDictionary * dict = nil;
		NSMutableArray * processingRequests = [NSMutableArray array];

		//get the request from the queue
		@synchronized(self) {
			request = [requests firstObject];
			if(!request)
				continue;
			
			[processingRequests addObject:request];
			[requests removeObject:request];
			
			//get the request rectionary for merge
			dict = [[request requestDictionary] mutableCopy];
			for(int i = 0; i < requests.count; ++i)
			{
				PWRequest * req = [requests objectAtIndex:i];
				
				//merge requests only if they are the same class
				if([req isKindOfClass:[request class]])
				{
					//add values from new request
					NSDictionary *newDict = [req requestDictionary];
					for(id<NSCopying> key in [newDict allKeys])
					{
						NSObject *value = [newDict objectForKey:key];
						
						//handle dictionaries in the request separately (applies to setTags method)
						if([value isKindOfClass:[NSDictionary class]]) {
							NSMutableDictionary * oldDict = [[dict objectForKey:key] mutableCopy];
							
							if(oldDict && [oldDict isKindOfClass:[NSDictionary class]]) {
								[oldDict addEntriesFromDictionary:(NSDictionary *)value];
								value = oldDict;
							}
						}
						
						[dict setObject:value forKey:key];
					}
					
					[processingRequests addObject:req];
					[requests removeObject:req];
					--i;
				}
			}
		}

		//send it
		NSError * error = nil;
		NSDictionary *responseDict = [self sendRequestInternal:request withDict: dict error:&error];
		for(PWRequest * req in processingRequests) {
			if(error)
				req.error = error;
			
			//propagate the result to other requests
			if(responseDict && req != request)
				[req parseResponse:responseDict];
			
			//mark as processed
			req.processed = YES;
		}
	}}
}

- (BOOL) sendRequest: (PWRequest *) request error:(NSError **)retError {
	//at the moment we queue only setTags requests
	if(![request isKindOfClass:[PWSetTagsRequest class]]) {
		NSDictionary * dict = [request requestDictionary];
		return [self sendRequestInternal:request withDict:dict error:retError] != nil;
	}
	
	//adding request to the queue
	@synchronized(self) {
		[requests addObject:request];
	}
	
	//sleep until it's processed
	while(!request.processed) {
		sleep(1);
	}
	
	//return error value if set
	if(request.error) {
		if(retError)
			*retError = request.error;
		
		return NO;
	}
		
	return YES;
}

- (NSDictionary *) sendRequestInternal: (PWRequest *) request withDict:(NSDictionary *)requestDict error:(NSError **)retError {
	
	//this method could be called in background
	__block NSInteger backgroundTaskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler: ^{
		[[UIApplication sharedApplication] endBackgroundTask:backgroundTaskId];
		backgroundTaskId = UIBackgroundTaskInvalid;
	}];
	
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:requestDict options:0 error:nil];
	NSString *requestString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
	NSString *jsonRequestData = [NSString stringWithFormat:@"{\"request\":%@}", requestString];

	//get the base url
	NSString *serviceAddressUrl = [[NSUserDefaults standardUserDefaults] objectForKey:@"Pushwoosh_BASEURL"];
	if(!serviceAddressUrl)
		serviceAddressUrl = [self defaultBaseUrl];

	[[NSUserDefaults standardUserDefaults] setObject:serviceAddressUrl forKey:@"Pushwoosh_BASEURL"];

	//request part
	NSString *requestUrl = [serviceAddressUrl stringByAppendingString:[request methodName]];
	
	PWLog(@"Sending request: %@", jsonRequestData);
	PWLog(@"To urL %@", requestUrl);
	
	NSMutableURLRequest *urlRequest = [[NSMutableURLRequest alloc] initWithURL:[NSURL URLWithString:requestUrl]];
	[urlRequest setHTTPMethod:@"POST"];
	[urlRequest addValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
	[urlRequest setHTTPBody:[jsonRequestData dataUsingEncoding:NSUTF8StringEncoding]];
	
	//Send data to server
	NSHTTPURLResponse *response = nil;
	NSError *error = nil;
	NSData * responseData = [NSURLConnection sendSynchronousRequest:urlRequest returningResponse:&response error:&error];
	urlRequest = nil;
	
	request.error = error;
	
	if(retError)
		*retError = error;
	
	NSString *responseString = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
	PWLog(@"Response \"%ld %@\": string: %@", (long)[response statusCode], [NSHTTPURLResponse localizedStringForStatusCode:[response statusCode]], responseString);
    
    NSDictionary *jsonResult = [NSJSONSerialization JSONObjectWithData:[responseString dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
	
	if(!jsonResult || [jsonResult objectForKey:@"status_code"] == nil) {
		NSString *serviceAddressUrl = [self defaultBaseUrl];
		[[NSUserDefaults standardUserDefaults] setObject:serviceAddressUrl forKey:@"Pushwoosh_BASEURL"];
	}
	
	// honor base url switch
	NSString *newBaseUrl = [jsonResult objectForKey:@"base_url"];
	if(newBaseUrl) {
		[[NSUserDefaults standardUserDefaults] setObject:newBaseUrl forKey:@"Pushwoosh_BASEURL"];
	}
	
	NSInteger pushwooshResult = [[jsonResult objectForKey:@"status_code"] intValue];
	if (response.statusCode != 200 || pushwooshResult != 200)
	{
		if(retError && !error)
			*retError = [NSError errorWithDomain:@"com.pushwoosh" code:response.statusCode userInfo:jsonResult];

		[[UIApplication sharedApplication] endBackgroundTask:backgroundTaskId];
		return nil;
	}
	
	NSDictionary *responseDict = [NSDictionary dictionary];
	if (jsonResult && [jsonResult isKindOfClass:[NSDictionary class]])
	{
		responseDict = [jsonResult objectForKey:@"response"];
		if(responseDict && ![responseDict isKindOfClass:[NSNull class]] && [responseDict isKindOfClass:[NSDictionary class]])
		{
			[request parseResponse:responseDict];
		}
	}
	
	[[UIApplication sharedApplication] endBackgroundTask:backgroundTaskId];
	return responseDict;
}

@end
