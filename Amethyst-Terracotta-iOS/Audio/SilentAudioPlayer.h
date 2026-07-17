//
//  SilentAudioPlayer.h
//  TerracottaHelper
//
//  Keeps the app alive in background by playing a looping silent audio.
//
//  WHY THIS EXISTS:
//  iOS suspends apps that go to background unless they have an active
//  background mode. The "audio" background mode (declared in Info.plist)
//  keeps the app alive as long as audio is actively playing. We generate
//  a 1-second silent WAV in memory and loop it indefinitely.
//
//  This ensures EasyTier's virtual-network threads keep running when the
//  user switches to Amethyst-iOS to play Minecraft. Without this, iOS
//  would suspend the helper app within ~5 seconds and all P2P connections
//  would drop.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SilentAudioPlayer : NSObject

/// Shared singleton.
+ (instancetype)shared;

/// Begin playing silent audio. Safe to call multiple times — subsequent
/// calls are no-ops. Activates the AVAudioSession with .playback category.
- (void)start;

/// Stop playing and deactivate the session. Called on app termination.
- (void)stop;

/// Whether audio is currently playing.
@property (nonatomic, readonly) BOOL isPlaying;

@end

NS_ASSUME_NONNULL_END
