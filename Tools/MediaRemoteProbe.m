#import <Cocoa/Cocoa.h>
#import <dlfcn.h>
#import "../YandexMiniPlayer/Playback/MediaRemoteBridge.h"

typedef void (*ProbeGetInfoFunction)(dispatch_queue_t, void (^)(CFDictionaryRef));

int main(void) {
    @autoreleasepool {
        fprintf(stderr, "MediaRemote available: %s\n", MediaRemoteBridge.isAvailable ? "yes" : "no");
        void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        ProbeGetInfoFunction rawGetInfo = (ProbeGetInfoFunction)dlsym(handle, "MRMediaRemoteGetNowPlayingInfo");
        dispatch_semaphore_t rawSemaphore = dispatch_semaphore_create(0);
        rawGetInfo(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(CFDictionaryRef rawInfo) {
            NSLog(@"Raw Now Playing: %@", (__bridge NSDictionary *)rawInfo ?: @"<empty>");
            dispatch_semaphore_signal(rawSemaphore);
        });
        dispatch_semaphore_wait(rawSemaphore, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC));
        [MediaRemoteBridge getNowPlayingInfoWithCompletion:^(NSDictionary *info) {
            NSLog(@"Now Playing: %@", info ?: @"<empty>");
            [NSApp terminate:nil];
        }];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            fprintf(stderr, "Timed out waiting for MediaRemote\n");
            [NSApp terminate:nil];
        });
        [NSApplication sharedApplication];
        [NSApp run];
    }
    return 0;
}
