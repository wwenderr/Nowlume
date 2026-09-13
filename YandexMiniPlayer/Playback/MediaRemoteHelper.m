#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*MRHelperGetInfoFunction)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*MRHelperGetPlayingFunction)(dispatch_queue_t, void (^)(BOOL));
typedef void (*MRHelperRegisterFunction)(dispatch_queue_t);
typedef void (*MRHelperSetCanBeNowPlayingFunction)(BOOL);
typedef BOOL (*MRHelperSendCommandFunction)(NSInteger, NSDictionary *);

static void *HelperMediaRemoteHandle(void) {
    return dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW | RTLD_GLOBAL);
}

static void PrintJSON(NSDictionary *dictionary) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:dictionary ?: @{} options:0 error:nil];
    if (json.length > 0) {
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
    } else {
        fputs("{}\n", stdout);
    }
    fflush(stdout);
}

/// Loaded by the Apple-signed /usr/bin/perl host. This restores read access to
/// the legacy MediaRemote callback on macOS 15.4 and newer.
__attribute__((visibility("default"))) void YMPReadNowPlaying(void) {
    @autoreleasepool {
        void *handle = HelperMediaRemoteHandle();
        if (handle == NULL) { PrintJSON(@{}); return; }

        dispatch_queue_t queue = dispatch_queue_create("com.danila.YandexMiniPlayer.helper", DISPATCH_QUEUE_SERIAL);
        MRHelperRegisterFunction registerNotifications = (MRHelperRegisterFunction)dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications");
        MRHelperSetCanBeNowPlayingFunction setCanBeNowPlaying = (MRHelperSetCanBeNowPlayingFunction)dlsym(handle, "MRMediaRemoteSetCanBeNowPlayingApplication");
        MRHelperGetInfoFunction getInfo = (MRHelperGetInfoFunction)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
        MRHelperGetPlayingFunction getPlaying = (MRHelperGetPlayingFunction)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");

        if (registerNotifications != NULL) { registerNotifications(queue); }
        if (setCanBeNowPlaying != NULL) { setCanBeNowPlaying(NO); }
        if (getInfo == NULL) { PrintJSON(@{}); return; }

        dispatch_group_t group = dispatch_group_create();
        __block NSDictionary *rawInfo;
        __block NSNumber *isPlaying;

        dispatch_group_enter(group);
        getInfo(queue, ^(NSDictionary *information) {
            rawInfo = [information copy];
            dispatch_group_leave(group);
        });

        if (getPlaying != NULL) {
            dispatch_group_enter(group);
            getPlaying(queue, ^(BOOL playing) {
                isPlaying = @(playing);
                dispatch_group_leave(group);
            });
        }

        long result = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
        if (result != 0 || rawInfo.count == 0) { PrintJSON(@{}); return; }

        NSDictionary<NSString *, NSString *> *keys = @{
            @"title": @"kMRMediaRemoteNowPlayingInfoTitle",
            @"artist": @"kMRMediaRemoteNowPlayingInfoArtist",
            @"album": @"kMRMediaRemoteNowPlayingInfoAlbum",
            @"duration": @"kMRMediaRemoteNowPlayingInfoDuration",
            @"elapsedTime": @"kMRMediaRemoteNowPlayingInfoElapsedTime",
            @"playbackRate": @"kMRMediaRemoteNowPlayingInfoPlaybackRate",
            @"artworkData": @"kMRMediaRemoteNowPlayingInfoArtworkData",
            @"identifier": @"kMRMediaRemoteNowPlayingInfoUniqueIdentifier"
        };

        NSMutableDictionary *output = [NSMutableDictionary dictionary];
        [keys enumerateKeysAndObjectsUsingBlock:^(NSString *destinationKey, NSString *sourceKey, BOOL *stop) {
            id value = rawInfo[sourceKey];
            if ([value isKindOfClass:NSData.class]) {
                output[destinationKey] = [value base64EncodedStringWithOptions:0];
            } else if ([value isKindOfClass:NSDate.class]) {
                output[destinationKey] = @([value timeIntervalSince1970]);
            } else if (value != nil && [NSJSONSerialization isValidJSONObject:@[value]]) {
                output[destinationKey] = value;
            }
        }];
        NSNumber *rawPlaybackRate = rawInfo[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
        // Require both the selected item's rate and the system playback state
        // when both are available. The item rate can remain stuck at 1.0 after
        // playback has stopped, while the global state can briefly refer to a
        // different registered session. Combining them avoids both stale audio
        // and inactive browser tabs being reported as actively playing.
        BOOL hasItemPlaybackRate = [rawPlaybackRate isKindOfClass:NSNumber.class];
        BOOL hasSystemPlaybackState = [isPlaying isKindOfClass:NSNumber.class];
        BOOL itemIsPlaying = hasItemPlaybackRate && rawPlaybackRate.doubleValue > 0.01;
        BOOL playing = hasItemPlaybackRate && hasSystemPlaybackState
            ? itemIsPlaying && isPlaying.boolValue
            : (hasItemPlaybackRate ? itemIsPlaying : isPlaying.boolValue);
        output[@"isPlaying"] = @(playing);
        output[@"playbackRate"] = playing ? @1.0 : @0.0;

        // Several Electron players publish elapsedTime as a fixed baseline
        // together with a timestamp. Convert it to a live value here.
        NSNumber *elapsed = rawInfo[@"kMRMediaRemoteNowPlayingInfoElapsedTime"];
        NSDate *timestamp = rawInfo[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
        if ([elapsed isKindOfClass:NSNumber.class]) {
            NSTimeInterval liveElapsed = elapsed.doubleValue;
            if (playing && [timestamp isKindOfClass:NSDate.class]) {
                liveElapsed += MAX(0, -timestamp.timeIntervalSinceNow);
            }
            output[@"elapsedTime"] = @(liveElapsed);
        }
        PrintJSON(output);
    }
}

__attribute__((visibility("default"))) void YMPPerformCommand(void) {
    @autoreleasepool {
        void *handle = HelperMediaRemoteHandle();
        MRHelperSendCommandFunction send = handle == NULL ? NULL : (MRHelperSendCommandFunction)dlsym(handle, "MRMediaRemoteSendCommand");
        NSString *rawCommand = NSProcessInfo.processInfo.environment[@"YMP_COMMAND"];
        BOOL success = send != NULL && rawCommand != nil && send(rawCommand.integerValue, nil);
        // MediaRemote dispatches commands asynchronously. Keep the signed host
        // alive long enough for mediaremoted to deliver the command.
        if (success) { [NSThread sleepForTimeInterval:0.55]; }
        PrintJSON(@{ @"success": @(success) });
    }
}
