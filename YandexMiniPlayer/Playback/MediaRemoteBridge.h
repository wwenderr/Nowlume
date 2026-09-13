#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// A tiny dynamic bridge around macOS MediaRemote. No private headers or
/// compile-time private-framework link is required.
@interface MediaRemoteBridge : NSObject
+ (BOOL)isAvailable;
+ (void)getNowPlayingInfoWithCompletion:(void (^)(NSDictionary * _Nullable info))completion;
+ (BOOL)sendCommand:(NSInteger)command;
@end

NS_ASSUME_NONNULL_END
