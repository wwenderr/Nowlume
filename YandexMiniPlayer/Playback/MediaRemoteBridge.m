#import "MediaRemoteBridge.h"
#import <dlfcn.h>

typedef void (*MRGetNowPlayingInfoFunction)(dispatch_queue_t, void (^)(CFDictionaryRef _Nullable));
typedef BOOL (*MRSendCommandFunction)(NSInteger, CFDictionaryRef _Nullable);
typedef void (*MRRegisterForNowPlayingNotificationsFunction)(dispatch_queue_t);
typedef void (*MRSetWantsNowPlayingNotificationsFunction)(BOOL);
typedef void (*MRSetCanBeNowPlayingApplicationFunction)(BOOL);

static const NSInteger ControllerMaximumPollCount = 25;
static const uint64_t ControllerPollIntervalNanoseconds = 100 * NSEC_PER_MSEC;

static CFStringRef MediaRemoteKey(const char *symbolName, CFStringRef fallback);

static void *MediaRemoteHandle(void) {
    static void *handle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // RTLD_GLOBAL is required on macOS 15.4+ so the new Objective-C
        // MediaRemote classes are registered and visible via NSClassFromString.
        handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW | RTLD_GLOBAL);
    });
    return handle;
}

static id SafeValueForKey(id object, NSString *key) {
    if (object == nil) { return nil; }
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSDictionary *BuildInfoDictionaryFromControllerResponse(id response) {
    if (response == nil) { return nil; }

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    NSNumber *rate = SafeValueForKey(response, @"playbackRate");
    NSNumber *state = SafeValueForKey(response, @"playbackState");
    if ([rate isKindOfClass:NSNumber.class]) {
        info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] =
            rate.doubleValue == 0 && state.unsignedIntegerValue == 1 ? @1.0 : rate;
    } else if ([state isKindOfClass:NSNumber.class]) {
        info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] = state.unsignedIntegerValue == 1 ? @1.0 : @0.0;
    }

    id queue = SafeValueForKey(response, @"playbackQueue");
    NSArray *items = SafeValueForKey(queue, @"contentItems");
    if (![items isKindOfClass:NSArray.class] || items.count == 0) {
        return info.count > 0 ? info : nil;
    }

    NSInteger location = [SafeValueForKey(queue, @"location") integerValue];
    id item = location >= 0 && location < (NSInteger)items.count ? items[(NSUInteger)location] : items.firstObject;
    id metadata = SafeValueForKey(item, @"metadata");
    if (metadata == nil) { return info.count > 0 ? info : nil; }

    NSDictionary<NSString *, NSString *> *metadataKeys = @{
        @"title": @"kMRMediaRemoteNowPlayingInfoTitle",
        @"trackArtistName": @"kMRMediaRemoteNowPlayingInfoArtist",
        @"albumName": @"kMRMediaRemoteNowPlayingInfoAlbum",
        @"duration": @"kMRMediaRemoteNowPlayingInfoDuration",
        @"elapsedTime": @"kMRMediaRemoteNowPlayingInfoElapsedTime",
        @"uniqueIdentifier": @"kMRMediaRemoteNowPlayingInfoUniqueIdentifier"
    };
    [metadataKeys enumerateKeysAndObjectsUsingBlock:^(NSString *sourceKey, NSString *destinationKey, BOOL *stop) {
        id value = SafeValueForKey(metadata, sourceKey);
        if (value != nil) { info[destinationKey] = value; }
    }];

    // Artwork and a few app-specific fields are commonly stored here.
    NSDictionary *extra = SafeValueForKey(metadata, @"nowPlayingInfo");
    if ([extra isKindOfClass:NSDictionary.class]) {
        [extra enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            if (key != nil && value != nil && info[key] == nil) { info[key] = value; }
        }];
    }
    return info.count > 0 ? info : nil;
}

static id SharedNowPlayingController(void) {
    static id controller;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class destinationClass = NSClassFromString(@"MRDestination");
        Class configurationClass = NSClassFromString(@"MRNowPlayingControllerConfiguration");
        Class controllerClass = NSClassFromString(@"MRNowPlayingController");
        if (destinationClass == Nil || configurationClass == Nil || controllerClass == Nil) { return; }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id destination = [destinationClass performSelector:NSSelectorFromString(@"userSelectedDestination")];
        id configuration = [[configurationClass alloc]
            performSelector:NSSelectorFromString(@"initWithDestination:")
            withObject:destination];
        [configuration setValue:@NO forKey:@"singleShot"];
        [configuration setValue:@YES forKey:@"requestPlaybackState"];
        [configuration setValue:@YES forKey:@"requestPlaybackQueue"];

        controller = [[controllerClass alloc]
            performSelector:NSSelectorFromString(@"initWithConfiguration:")
            withObject:configuration];
        [controller performSelector:NSSelectorFromString(@"beginLoadingUpdates")];
#pragma clang diagnostic pop
    });
    return controller;
}

static void QueryViaNowPlayingController(void (^completion)(NSDictionary * _Nullable)) {
    dispatch_async(dispatch_get_main_queue(), ^{
        id controller = SharedNowPlayingController();
        if (controller == nil) {
            completion(nil);
            return;
        }

        __block NSInteger pollCount = 0;
        __block dispatch_source_t timer = dispatch_source_create(
            DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(
            timer,
            DISPATCH_TIME_NOW,
            ControllerPollIntervalNanoseconds,
            ControllerPollIntervalNanoseconds / 10);
        dispatch_source_set_event_handler(timer, ^{
            pollCount += 1;
            NSDictionary *info = BuildInfoDictionaryFromControllerResponse(
                SafeValueForKey(controller, @"response"));
            BOOL hasMetadata = info[@"kMRMediaRemoteNowPlayingInfoTitle"] != nil;
            if (hasMetadata || pollCount >= ControllerMaximumPollCount) {
                dispatch_source_cancel(timer);
                timer = nil;
                completion(hasMetadata ? info : nil);
            }
        });
        dispatch_resume(timer);
    });
}

static NSDictionary *NormalizeInfoDictionary(NSDictionary *info) {
    if (info.count == 0) { return nil; }

    CFStringRef titleKey = MediaRemoteKey("kMRMediaRemoteNowPlayingInfoTitle", CFSTR("kMRMediaRemoteNowPlayingInfoTitle"));
    CFStringRef artistKey = MediaRemoteKey("kMRMediaRemoteNowPlayingInfoArtist", CFSTR("kMRMediaRemoteNowPlayingInfoArtist"));
    CFStringRef albumKey = MediaRemoteKey("kMRMediaRemoteNowPlayingInfoAlbum", CFSTR("kMRMediaRemoteNowPlayingInfoAlbum"));
    CFStringRef durationKey = MediaRemoteKey("kMRMediaRemoteNowPlayingInfoDuration", CFSTR("kMRMediaRemoteNowPlayingInfoDuration"));
    CFStringRef elapsedKey = MediaRemoteKey("kMRMediaRemoteNowPlayingInfoElapsedTime", CFSTR("kMRMediaRemoteNowPlayingInfoElapsedTime"));
    CFStringRef rateKey = MediaRemoteKey("kMRMediaRemoteNowPlayingInfoPlaybackRate", CFSTR("kMRMediaRemoteNowPlayingInfoPlaybackRate"));
    CFStringRef artworkKey = MediaRemoteKey("kMRMediaRemoteNowPlayingInfoArtworkData", CFSTR("kMRMediaRemoteNowPlayingInfoArtworkData"));
    CFStringRef identifierKey = MediaRemoteKey("kMRMediaRemoteNowPlayingInfoUniqueIdentifier", CFSTR("kMRMediaRemoteNowPlayingInfoUniqueIdentifier"));

    NSDictionary<NSString *, NSString *> *keys = @{
        @"title": (__bridge NSString *)titleKey,
        @"artist": (__bridge NSString *)artistKey,
        @"album": (__bridge NSString *)albumKey,
        @"duration": (__bridge NSString *)durationKey,
        @"elapsedTime": (__bridge NSString *)elapsedKey,
        @"playbackRate": (__bridge NSString *)rateKey,
        @"artworkData": (__bridge NSString *)artworkKey,
        @"identifier": (__bridge NSString *)identifierKey
    };
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [keys enumerateKeysAndObjectsUsingBlock:^(NSString *destinationKey, NSString *sourceKey, BOOL *stop) {
        id value = info[sourceKey];
        if (value != nil) { result[destinationKey] = value; }
    }];
    return result.count > 0 ? result : nil;
}

static CFStringRef MediaRemoteKey(const char *symbolName, CFStringRef fallback) {
    void *handle = MediaRemoteHandle();
    if (handle == NULL) { return fallback; }
    CFStringRef const *value = (CFStringRef const *)dlsym(handle, symbolName);
    return (value != NULL && *value != NULL) ? *value : fallback;
}

static void RegisterForNowPlayingIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = MediaRemoteHandle();
        if (handle == NULL) { return; }

        MRSetWantsNowPlayingNotificationsFunction setWants =
            (MRSetWantsNowPlayingNotificationsFunction)dlsym(handle, "MRMediaRemoteSetWantsNowPlayingNotifications");
        if (setWants != NULL) { setWants(YES); }

        MRRegisterForNowPlayingNotificationsFunction registerNotifications =
            (MRRegisterForNowPlayingNotificationsFunction)dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
        if (registerNotifications != NULL) {
            registerNotifications(dispatch_get_main_queue());
        }

        MRSetCanBeNowPlayingApplicationFunction setCanBeNowPlaying =
            (MRSetCanBeNowPlayingApplicationFunction)dlsym(handle, "MRMediaRemoteSetCanBeNowPlayingApplication");
        if (setCanBeNowPlaying != NULL) { setCanBeNowPlaying(NO); }
    });
}

@implementation MediaRemoteBridge

+ (BOOL)isAvailable {
    void *handle = MediaRemoteHandle();
    return handle != NULL && dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") != NULL;
}

+ (void)getNowPlayingInfoWithCompletion:(void (^)(NSDictionary * _Nullable))completion {
    RegisterForNowPlayingIfNeeded();
    void *handle = MediaRemoteHandle();
    MRGetNowPlayingInfoFunction getInfo = handle == NULL ? NULL : (MRGetNowPlayingInfoFunction)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
    if (getInfo == NULL) {
        completion(nil);
        return;
    }

    getInfo(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(CFDictionaryRef rawInfo) {
        NSDictionary *info = (__bridge NSDictionary *)rawInfo;
        if (info.count == 0) {
            // The legacy callback is intentionally empty on macOS 15.4+.
            QueryViaNowPlayingController(^(NSDictionary *controllerInfo) {
                completion(NormalizeInfoDictionary(controllerInfo));
            });
            return;
        }
        completion(NormalizeInfoDictionary(info));
    });
}

+ (BOOL)sendCommand:(NSInteger)command {
    void *handle = MediaRemoteHandle();
    MRSendCommandFunction send = handle == NULL ? NULL : (MRSendCommandFunction)dlsym(handle, "MRMediaRemoteSendCommand");
    return send != NULL ? send(command, NULL) : NO;
}

@end
