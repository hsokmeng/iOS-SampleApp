//
//  StationWebService.m
//  TagTheTram
//
//  Created by David Barthelemy on 09/09/13.
//  Copyright (c) 2013 David Barthelemy, iMakeit4U. All rights reserved.
//

#import "StationWebService.h"
#import "Station+CRUD.h"

static StationWebService *_sharedInstance = nil;

@interface StationWebService ()
@property (nonatomic, assign) BOOL isRunning;
@end

@implementation StationWebService

#pragma mark - Singleton methods

+ (StationWebService *)sharedInstance
{
    if (_sharedInstance == nil) {
        _sharedInstance = [[super allocWithZone:NULL] init];
    }
    return _sharedInstance;
}

+ (id)allocWithZone:(NSZone *)zone
{
    return [[self sharedInstance] retain];
}

- (id)copyWithZone:(NSZone *)zone
{
    return self;
}

- (id)retain
{
    return self;
}

- (NSUInteger)retainCount
{
    return NSUIntegerMax;  //denotes an object that cannot be released
}

- (oneway void)release
{
    //do nothing
}

- (id)autorelease
{
    return self;
}


#pragma mark - Public methods

- (BOOL)fetchStations
{
    /*
     * Given the low complexity of the Web Service, here is a straitforward implementation which give good performances (e.g. no need for a secondary 
     *  NSMAnagedObjectContext and associated merge as all CRUD operations are executed on the main thread) and responsiveness (thanks to GCD usage)
     *  without being too much complex.
     *
     * For more advanced features (Authentication, Security, Download Progress) a NSURLConnection would be required in place of this basic approach.
     * I would be please to share with you my coding techniques for such use-cases.
     */
    if (self.isRunning) {
        return YES;
    }
    else {
        self.isRunning = YES;
        [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSURL *restApiUrl = [NSURL URLWithString:@"http://modulaweb.fr/apitam/?request=getStopsList&fullInfos=1"];
            NSError *restApiError = nil;
            
            NSData *restApiData = [NSData dataWithContentsOfURL:restApiUrl options:0 error:&restApiError];
            
            if (restApiData) {
                BOOL isValidFormat = NO;
                
                NSError *parseError = nil;
                id resultObject = [NSJSONSerialization JSONObjectWithData:restApiData options:0 error:&parseError];
                if (resultObject) {
                    if ([resultObject isKindOfClass:[NSDictionary class]]) {
                        NSDictionary *resultDictionary = (NSDictionary *)resultObject;
                        if ([[resultDictionary objectForKey:@"status"] isEqualToString:@"ok"]) {
                            //
                            // Status is correct
                            //
                            id responseObject = [resultDictionary objectForKey:@"response"];
                            if ([responseObject isKindOfClass:[NSDictionary class]]) {
                                NSDictionary *responseDictionary = (NSDictionary *)responseObject;
                                if ([responseDictionary count]) {
                                    //
                                    // Response is not empty
                                    //
                                    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
                                    [numberFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
                                    
                                    for (NSString *eachKey in responseDictionary) {
                                        id eachGroupObject = [responseDictionary objectForKey:eachKey];
                                        if ([eachGroupObject isKindOfClass:[NSArray class]]) {
                                            NSArray *eachGroupArray = (NSArray *)eachGroupObject;
                                            if ([eachGroupArray count]) {
                                                //
                                                // the station group is not empty
                                                //
                                                for (id eachStationObject in eachGroupArray) {
                                                    if ([eachStationObject isKindOfClass:[NSDictionary class]]) {
                                                        NSDictionary *eachStationDictionary = (NSDictionary *)eachStationObject;
                                                        if ([eachStationDictionary count]) {
                                                            id eachStationDescriptionObject = [eachStationDictionary valueForKey:[eachStationDictionary allKeys][0]];
                                                            if ([eachStationDescriptionObject isKindOfClass:[NSDictionary class]]) {
                                                                //
                                                                // Retrieve a station
                                                                //
                                                                NSDictionary *eachStationDescriptionDictionary = (NSDictionary *)eachStationDescriptionObject;
                                                                NSString *eachId = [eachStationDescriptionDictionary objectForKey:@"id"];
                                                                NSString *eachName = [eachStationDescriptionDictionary objectForKey:@"name"];
                                                                NSString *eachLatitudeStr = [eachStationDescriptionDictionary objectForKey:@"latitude"];
                                                                NSString *eachLongitudeStr = [eachStationDescriptionDictionary objectForKey:@"longitude"];
                                                                NSString *theTown = [[eachStationDescriptionDictionary objectForKey:@"town"] uppercaseString];
                                                                
                                                                NSNumber *eachLatitude = [numberFormatter numberFromString:eachLatitudeStr];
                                                                NSNumber *eachLongitude = [numberFormatter numberFromString:eachLongitudeStr];
                                                                
                                                                if (([eachId length] > 0) &&
                                                                    ([eachName length] > 0) &&
                                                                    ([theTown isEqualToString:@"MONTPELLIER"])) {
                                                                    isValidFormat = YES; // We consider valid format if at least one entry is properly decoded.
                                                                    
                                                                    dispatch_async(dispatch_get_main_queue() , ^{
                                                                        [Station stationWithId:eachId
                                                                                          name:eachName
                                                                                      latitude:eachLatitude
                                                                                     longitude:eachLongitude];
                                                                    });
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                if ((isValidFormat == NO) || (parseError)) {
                    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:@"JSON Parsing error" forKey:NSLocalizedDescriptionKey];
                    NSError *customError = [NSError errorWithDomain:kWebServiceAPIErrorDomain code:JSONParsingErrorCode userInfo:userInfo];
                    
                    if ([self.delegate respondsToSelector:@selector(fetchStationsDidFailedWithError:)]) {
                        dispatch_async(dispatch_get_main_queue() , ^{
                            [self.delegate fetchStationsDidFailedWithError:customError];
                        });
                    }
                }
                else {
                    if ([self.delegate respondsToSelector:@selector(fetchStationsDidSucceed)]) {
                        dispatch_async(dispatch_get_main_queue() , ^{
                            [self.delegate fetchStationsDidSucceed];
                        });
                    }
                }
            }
            else {
                if (restApiError) {
                    if ([self.delegate respondsToSelector:@selector(fetchStationsDidFailedWithError:)]) {
                        dispatch_async(dispatch_get_main_queue() , ^{
                            [self.delegate fetchStationsDidFailedWithError:restApiError];
                        });
                    }
                }
            }
            [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
            self.isRunning = NO;
        });
    }
    return self.isRunning;
}

@end
