//
//  SilentAudioPlayer.m
//  TerracottaHelper
//

#import "SilentAudioPlayer.h"
#import "TerracottaLog.h"

@interface SilentAudioPlayer ()
@property (nonatomic, strong) AVAudioPlayer *player;
@property (nonatomic, assign) BOOL isPlaying;
@end

@implementation SilentAudioPlayer

+ (instancetype)shared {
    static SilentAudioPlayer *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SilentAudioPlayer alloc] init];
    });
    return instance;
}

- (void)start {
    if (self.isPlaying) return;

    // Configure the audio session for background audio playback.
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *err = nil;

    // .playback category: allows audio even in silent mode and in background.
    // The "audio" background mode in Info.plist must be present.
    [session setCategory:AVAudioSessionCategoryPlayback
             mode:AVAudioSessionModeDefault
          options:0
            error:&err];
    if (err) {
        TerracottaLogError(@"Cannot set audio session category: %@", err);
        return;
    }

    [session setActive:YES error:&err];
    if (err) {
        TerracottaLogError(@"Cannot activate audio session: %@", err);
        return;
    }

    // Generate a 1-second silent WAV file in memory.
    NSData *silentWAV = [self generateSilentWAV];
    if (!silentWAV) {
        TerracottaLogError(@"Cannot generate silent WAV data.");
        return;
    }

    self.player = [[AVAudioPlayer alloc] initWithData:silentWAV error:&err];
    if (err || !self.player) {
        TerracottaLogError(@"Cannot init AVAudioPlayer: %@", err);
        return;
    }

    self.player.numberOfLoops = -1;  // Loop forever
    self.player.volume = 0.0;        // Mute — we only need the session active

    if (![self.player play]) {
        TerracottaLogError(@"AVAudioPlayer failed to start playback.");
        return;
    }

    self.isPlaying = YES;
    TerracottaLogInfo(@"SilentAudioPlayer started — app will stay alive in background.");
}

- (void)stop {
    if (!self.isPlaying) return;
    [self.player stop];
    self.player = nil;

    NSError *err = nil;
    [[AVAudioSession sharedInstance] setActive:NO
                           withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                     error:&err];
    self.isPlaying = NO;
    TerracottaLogInfo(@"SilentAudioPlayer stopped.");
}

/// Generate a minimal 1-second mono 16-bit PCM WAV file (all silence).
/// Total size: 44-byte header + 88200 bytes data = ~88 KB.
- (NSData *)generateSilentWAV {
    // PCM parameters
    const uint32_t sampleRate = 44100;
    const uint16_t numChannels = 1;
    const uint16_t bitsPerSample = 16;
    const double durationSeconds = 1.0;

    uint32_t numSamples = (uint32_t)(sampleRate * durationSeconds);
    uint32_t dataSize = numSamples * numChannels * (bitsPerSample / 8);
    uint32_t byteRate = sampleRate * numChannels * (bitsPerSample / 8);
    uint16_t blockAlign = numChannels * (bitsPerSample / 8);

    // Total file size = 44 (header) + dataSize
    NSMutableData *wav = [NSMutableData dataWithCapacity:44 + dataSize];

    // Helper to append raw bytes
    #define APPEND_BYTES(ptr, size) [wav appendBytes:(ptr) length:(size)]
    #define APPEND_U32(val) do { uint32_t _v = (val); APPEND_BYTES(&_v, 4); } while(0)
    #define APPEND_U16(val) do { uint16_t _v = (val); APPEND_BYTES(&_v, 2); } while(0)

    // RIFF header
    APPEND_BYTES("RIFF", 4);
    APPEND_U32(36 + dataSize);   // ChunkSize = file size - 8
    APPEND_BYTES("WAVE", 4);

    // fmt sub-chunk
    APPEND_BYTES("fmt ", 4);
    APPEND_U32(16);              // Subchunk1Size (PCM = 16)
    APPEND_U16(1);               // AudioFormat (1 = PCM)
    APPEND_U16(numChannels);
    APPEND_U32(sampleRate);
    APPEND_U32(byteRate);
    APPEND_U16(blockAlign);
    APPEND_U16(bitsPerSample);

    // data sub-chunk
    APPEND_BYTES("data", 4);
    APPEND_U32(dataSize);

    // Append silence (all zero bytes). NSMutableData already initializes to
    // zero, but we explicitly fill to be safe.
    static const uint8_t zeros[4096] = {0};
    uint32_t remaining = dataSize;
    while (remaining >= sizeof(zeros)) {
        APPEND_BYTES(zeros, sizeof(zeros));
        remaining -= sizeof(zeros);
    }
    if (remaining > 0) {
        APPEND_BYTES(zeros, remaining);
    }

    #undef APPEND_BYTES
    #undef APPEND_U32
    #undef APPEND_U16

    return wav;
}

@end
