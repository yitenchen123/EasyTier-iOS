//
//  TerracottaBridge.h
//  Amethyst
//
//  Objective-C wrapper around the C ABI exposed by libterracotta.a
//  (see terracotta.h). Provides idiomatic NSString/NSDictionary/NSArray
//  interfaces and an NSURLSession-based fetcher for the public EasyTier
//  node list.
//
//  100% protocol-compatible with HMCL / FCL / ZalithLauncher2 — the actual
//  room-code, EasyTier config, Scaffolding protocol and FakeServer logic
//  all live inside libterracotta.a (the very same burningtnt/Terracotta
//  Rust code that ships inside libterracotta.so on Android).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Terracotta state machine values (mirrors Rust `AppState`).
typedef NS_ENUM(NSInteger, TerracottaState) {
    TerracottaStateUnknown        = -1,
    TerracottaStateWaiting        = 0,
    TerracottaStateHostScanning   = 1,
    TerracottaStateHostStarting   = 2,
    TerracottaStateHostOk         = 3,
    TerracottaStateGuestConnecting = 4,
    TerracottaStateGuestStarting  = 5,
    TerracottaStateGuestOk        = 6,
    TerracottaStateException      = 7,
};

/// Exception type when state == TerracottaStateException.
typedef NS_ENUM(NSInteger, TerracottaExceptionType) {
    TerracottaExceptionPingHostFail             = 0,
    TerracottaExceptionPingHostRst              = 1,
    TerracottaExceptionGuestEasytierCrash       = 2,
    TerracottaExceptionHostEasytierCrash        = 3,
    TerracottaExceptionPingServerRst            = 4,
    TerracottaExceptionScaffoldingInvalidResponse = 5,
};

/// Connection difficulty (mirrors Rust `ConnectionDifficulty`).
typedef NS_ENUM(NSInteger, TerracottaDifficulty) {
    TerracottaDifficultyUnknown = 0,
    TerracottaDifficultyEasiest,
    TerracottaDifficultySimple,
    TerracottaDifficultyMedium,
    TerracottaDifficultyTough,
};

/// One player profile (mirrors Rust `Profile`).
@interface TerracottaProfile : NSObject
@property (nonatomic, copy)   NSString *machineId;
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, copy)   NSString *vendor;
@property (nonatomic, copy)   NSString *kind;   // "HOST" | "LOCAL" | "GUEST"
@end

/// A snapshot of the Terracotta state. Immutable; -[TerracottaBridge pollState]
/// returns a fresh instance each call.
@interface TerracottaStateSnapshot : NSObject
@property (nonatomic) TerracottaState state;
@property (nonatomic) NSInteger index;          ///< monotonic state index
@property (nonatomic) NSInteger profileIndex;   ///< shared (profile-only) index
@property (nonatomic, copy, nullable)   NSString *roomCode;
@property (nonatomic, copy, nullable)   NSString *url;          ///< "127.0.0.1:25565" for guest-ok
@property (nonatomic) TerracottaDifficulty difficulty;
@property (nonatomic) TerracottaExceptionType exceptionType;
@property (nonatomic, copy, nullable)   NSArray<TerracottaProfile *> *profiles;

/// Human-readable, localized description of the state for UI display.
- (NSString *)localizedDescription;
@end

/// Thin Obj-C wrapper around the libterracotta.a C ABI.
///
/// Thread-safety: the underlying Rust code uses a global `parking_lot::Mutex`
/// to serialize state transitions, so it is safe to call these methods from
/// any thread. However, `-pollState` should typically be called from a
/// dedicated timer queue.
@interface TerracottaBridge : NSObject

/// Shared singleton. The first access does NOT call `terracotta_ios_start` —
/// you must call `-startWithWorkingDirectory:loggingPath:error:` explicitly.
+ (instancetype)shared;

/// Initialize the native Terracotta engine. Must be called once before any
/// other method. Idempotent: subsequent calls are no-ops and return YES.
///
///   workingDirectory  absolute path to a writable folder (POJAV_HOME).
///                      A `machine-id` file is created here.
///   loggingPath        absolute path to a log file, or nil to disable
///                      file logging (logs still go to stderr/Xcode).
///   error             filled on failure.
- (BOOL)startWithWorkingDirectory:(NSString *)workingDirectory
                      loggingPath:(nullable NSString *)loggingPath
                            error:(NSError **)error;

/// YES iff `-startWithWorkingDirectory:...` succeeded.
@property (nonatomic, readonly) BOOL isStarted;

/// Transition to Waiting. Idempotent.
- (void)setWaiting;

/// Host: begin scanning for a Minecraft "Open to LAN" world.
///   room    optional existing room code to reuse; nil to generate.
///   player  optional player name; nil uses "Terracotta Anonymous Host".
- (void)setScanningWithRoom:(nullable NSString *)room
                     player:(nullable NSString *)player;

/// Host (manual port mode): bypass multicast scanning and start hosting
/// directly with a user-supplied MC LAN port.
///
/// iOS 上多播接收受本地网络权限影响可能不可靠。用户在 MC 里点「对局域网开放」
/// 后会看到端口号，直接传入即可，完全跳过 MinecraftScanner 多播扫描。
///
///   room    optional existing room code to reuse; nil to generate.
///   port    the MC LAN port shown by Minecraft (e.g. 25565).
///   player  optional player name; nil uses "Terracotta Anonymous Host".
///
///   returns YES if hosting was initiated; NO if not in Waiting state.
- (BOOL)startHostWithRoom:(nullable NSString *)room
                     port:(uint16_t)port
                   player:(nullable NSString *)player;

/// Guest: join a room.
///   room    required room code (e.g. "U/ABCD-EFGH-IJKL-MNOP").
///   player  optional player name; nil uses "Terracotta Anonymous Guest".
///   returns YES if join was initiated; NO if the code is invalid or not in
///           Waiting state.
- (BOOL)setGuestingWithRoom:(NSString *)room
                     player:(nullable NSString *)player;

/// Verify a room code. Returns YES iff the code parses as a valid
/// SCAFFOLDING room (i.e. `terracotta_ios_verify_room_code` returns 3).
- (BOOL)verifyRoomCode:(NSString *)code;

/// Poll the current state. Returns nil if the engine isn't started.
- (nullable TerracottaStateSnapshot *)pollState;

/// Fetch the public EasyTier node list from
/// https://terracotta.glavo.site/nodes (same endpoint HMCL/FCL/ZL2 use).
/// Returns an array of peer URL strings (e.g. "tcp://1.2.3.4:11010").
/// This is purely informational on iOS — the Rust side already hardcodes
/// the 4 fallback peers in src/easytier/publics.rs.
- (void)fetchPublicNodesWithCompletion:(void (^)(NSArray<NSString *> *_Nullable nodes,
                                                 NSError *_Nullable error))completion;

/// Metadata: "<version>\n<timestamp>\n<easytier_version>".
- (nullable NSString *)metadata;

@end

NS_ASSUME_NONNULL_END
