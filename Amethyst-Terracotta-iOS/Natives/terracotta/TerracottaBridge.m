//
//  TerracottaBridge.m
//  Amethyst
//
//  Implements TerracottaBridge.h by calling the C ABI in libterracotta.a
//  (see terracotta.h). All string marshalling between Obj-C and Rust goes
//  through this file.
//

#import "TerracottaBridge.h"
#import "terracotta.h"
#import "TerracottaLog.h"

// Link against libterracotta.a. The C symbols are declared in terracotta.h
// and resolved at link time. No dlopen needed — Amethyst-iOS links the
// static library directly via CMakeLists.txt.

@implementation TerracottaProfile
@end

@implementation TerracottaStateSnapshot

- (NSString *)localizedDescription {
    switch (self.state) {
        case TerracottaStateWaiting:         return NSLocalizedString(@"Terracotta.Waiting", @"等待开始联机");
        case TerracottaStateHostScanning:    return NSLocalizedString(@"Terracotta.HostScanning", @"正在等待你在 Minecraft 中开放局域网世界…");
        case TerracottaStateHostStarting:    return NSLocalizedString(@"Terracotta.HostStarting", @"正在创建房间…");
        case TerracottaStateHostOk:          return NSLocalizedString(@"Terracotta.HostOk", @"房间已创建，分享邀请码给好友吧");
        case TerracottaStateGuestConnecting: return NSLocalizedString(@"Terracotta.GuestConnecting", @"正在连接房间…");
        case TerracottaStateGuestStarting:   return NSLocalizedString(@"Terracotta.GuestStarting", @"正在加入房间…");
        case TerracottaStateGuestOk:         return NSLocalizedString(@"Terracotta.GuestOk", @"已加入房间，可以连接服务器了");
        case TerracottaStateException:       return [self localizedExceptionDescription];
        default:                             return NSLocalizedString(@"Terracotta.Unknown", @"未知状态");
    }
}

- (NSString *)localizedExceptionDescription {
    switch (self.exceptionType) {
        case TerracottaExceptionPingHostFail:               return NSLocalizedString(@"Terracotta.Exception.PingHostFail", @"无法连接到房主，请检查邀请码或网络");
        case TerracottaExceptionPingHostRst:                return NSLocalizedString(@"Terracotta.Exception.PingHostRst", @"与房主的 Minecraft 连接被重置");
        case TerracottaExceptionGuestEasytierCrash:         return NSLocalizedString(@"Terracotta.Exception.GuestCrash", @"联机组件异常退出（房客）");
        case TerracottaExceptionHostEasytierCrash:          return NSLocalizedString(@"Terracotta.Exception.HostCrash", @"联机组件异常退出（房主）");
        case TerracottaExceptionPingServerRst:              return NSLocalizedString(@"Terracotta.Exception.PingServerRst", @"Minecraft 服务器无响应");
        case TerracottaExceptionScaffoldingInvalidResponse: return NSLocalizedString(@"Terracotta.Exception.Scaffolding", @"房间协议响应无效");
        default: return NSLocalizedString(@"Terracotta.Exception.Unknown", @"未知错误");
    }
}

@end

@interface TerracottaBridge ()
@property (nonatomic, assign) BOOL isStarted;
@end

@implementation TerracottaBridge

+ (instancetype)shared {
    static TerracottaBridge *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[TerracottaBridge alloc] init];
    });
    return instance;
}

- (BOOL)startWithWorkingDirectory:(NSString *)workingDirectory
                      loggingPath:(nullable NSString *)loggingPath
                            error:(NSError **)error {
    if (self.isStarted) {
        return YES;
    }
    if (workingDirectory.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"Terracotta" code:1
                                      userInfo:@{NSLocalizedDescriptionKey: @"workingDirectory is required"}];
        }
        return NO;
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *mkErr = nil;
    [fm createDirectoryAtPath:workingDirectory
          withIntermediateDirectories:YES attributes:nil error:&mkErr];
    if (mkErr) {
        if (error) *error = mkErr;
        return NO;
    }

    int loggingFd = -1;
    if (loggingPath.length > 0) {
        // Open the log file for writing. Rust takes ownership of the fd.
        int fd = open(loggingPath.UTF8String, O_WRONLY | O_CREAT | O_TRUNC, 0644);
        if (fd < 0) {
            TerracottaLogWarn(@"Cannot open log file %@: errno=%d", loggingPath, errno);
        } else {
            loggingFd = fd;
        }
    }

    int rc = terracotta_ios_start(workingDirectory.UTF8String, loggingFd);
    if (rc != 0) {
        if (error) {
            *error = [NSError errorWithDomain:@"Terracotta" code:rc
                                      userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"terracotta_ios_start returned %d", rc]}];
        }
        return NO;
    }

    self.isStarted = YES;
    TerracottaLogInfo(@"Terracotta engine started. dir=%@ log=%@", workingDirectory, loggingPath);
    return YES;
}

- (void)setWaiting {
    if (!self.isStarted) return;
    terracotta_ios_set_waiting();
}

- (void)setScanningWithRoom:(nullable NSString *)room
                     player:(nullable NSString *)player {
    if (!self.isStarted) return;
    terracotta_ios_set_scanning(room.UTF8String ?: NULL, player.UTF8String ?: NULL);
}

- (BOOL)setGuestingWithRoom:(NSString *)room
                     player:(nullable NSString *)player {
    if (!self.isStarted || room.length == 0) return NO;
    return terracotta_ios_set_guesting(room.UTF8String, player.UTF8String ?: NULL) == 1;
}

- (BOOL)verifyRoomCode:(NSString *)code {
    if (code.length == 0) return NO;
    return terracotta_ios_verify_room_code(code.UTF8String) == 3;
}

- (nullable TerracottaStateSnapshot *)pollState {
    if (!self.isStarted) return nil;
    char *raw = terracotta_ios_get_state();
    if (!raw) return nil;
    NSData *data = [NSData dataWithBytesNoCopy:raw
                                        length:strlen(raw)
                                  freeWhenDone:NO];
    // The Rust string is NUL-terminated; strlen gives the JSON length.
    TerracottaStateSnapshot *snap = [self parseStateJSON:data];
    terracotta_ios_free_string(raw);
    return snap;
}

- (nullable NSString *)metadata {
    char *raw = terracotta_ios_get_metadata();
    if (!raw) return nil;
    // Raw contains interior NULs; we need to consume the full buffer up to
    // the trailing NUL. The format is "v\0ts\0etv\0" — but CString.from_raw
    // expects a single NUL terminator. The Rust side used
    // CString::from_vec_unchecked which appends ONE trailing NUL, so the
    // interior NULs are part of the payload.
    //
    // We rebuild by scanning until double-NUL or end.
    size_t len = 0;
    const char *p = raw;
    // Find the end: Rust appended exactly one trailing NUL. So we cannot use
    // strlen. Instead, we know the format has exactly 2 interior NULs and 1
    // trailing. Scan until we've seen 3 NULs total.
    int nulCount = 0;
    while (nulCount < 3) {
        if (p[len] == 0) nulCount++;
        if (len > 4096) break;  // safety
        len++;
    }
    // Replace interior NULs with newlines for display.
    NSMutableData *display = [NSMutableData dataWithBytes:raw length:len];
    for (size_t i = 0; i < len - 1; i++) {
        if (((char *)display.bytes)[i] == 0) {
            ((char *)display.mutableBytes)[i] = '\n';
        }
    }
    NSString *result = [[NSString alloc] initWithData:display encoding:NSUTF8StringEncoding];
    terracotta_ios_free_string(raw);
    return result;
}

- (void)fetchPublicNodesWithCompletion:(void (^)(NSArray<NSString *> *_Nullable,
                                                 NSError *_Nullable))completion {
    // Same endpoint HMCL/FCL/ZalithLauncher2 use. Returns JSON like:
    // [{"url":"https://etnode.zkitefly.eu.org/node1","region":"CN"}, ...]
    NSURL *url = [NSURL URLWithString:@"https://terracotta.glavo.site/nodes"];
    NSURLSessionTask *task = [NSURLSession.sharedSession dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                if (completion) completion(@[], error);
                return;
            }
            NSError *jsonErr = nil;
            id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
            if (jsonErr || ![parsed isKindOfClass:[NSArray class]]) {
                if (completion) completion(@[], jsonErr);
                return;
            }
            NSMutableArray<NSString *> *nodes = [NSMutableArray array];
            for (NSDictionary *entry in (NSArray *)parsed) {
                NSString *u = entry[@"url"];
                if ([u isKindOfClass:[NSString class]] && u.length > 0) {
                    [nodes addObject:u];
                }
            }
            if (completion) completion(nodes, nil);
        }];
    [task resume];
}

#pragma mark - JSON parsing

- (TerracottaStateSnapshot *)parseStateJSON:(NSData *)data {
    NSError *err = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (err || ![json isKindOfClass:[NSDictionary class]]) {
        TerracottaLogWarn(@"Failed to parse Terracotta state JSON: %@", err);
        return nil;
    }

    TerracottaStateSnapshot *snap = [TerracottaStateSnapshot new];
    NSString *stateStr = json[@"state"];
    snap.state = [self stateFromString:stateStr];
    snap.index = [json[@"index"] integerValue];
    snap.profileIndex = [json[@"profile_index"] integerValue];
    snap.roomCode = json[@"room"];
    snap.url = json[@"url"];
    snap.difficulty = [self difficultyFromString:json[@"difficulty"]];
    snap.exceptionType = (TerracottaExceptionType)[json[@"type"] integerValue];
    snap.profiles = [self parseProfiles:json[@"profiles"]];
    return snap;
}

- (TerracottaState)stateFromString:(NSString *)s {
    if ([s isEqualToString:@"waiting"])         return TerracottaStateWaiting;
    if ([s isEqualToString:@"host-scanning"])   return TerracottaStateHostScanning;
    if ([s isEqualToString:@"host-starting"])   return TerracottaStateHostStarting;
    if ([s isEqualToString:@"host-ok"])         return TerracottaStateHostOk;
    if ([s isEqualToString:@"guest-connecting"]) return TerracottaStateGuestConnecting;
    if ([s isEqualToString:@"guest-starting"])  return TerracottaStateGuestStarting;
    if ([s isEqualToString:@"guest-ok"])        return TerracottaStateGuestOk;
    if ([s isEqualToString:@"exception"])       return TerracottaStateException;
    return TerracottaStateUnknown;
}

- (TerracottaDifficulty)difficultyFromString:(NSString *)s {
    if ([s isEqualToString:@"EASIEST"]) return TerracottaDifficultyEasiest;
    if ([s isEqualToString:@"SIMPLE"])  return TerracottaDifficultySimple;
    if ([s isEqualToString:@"MEDIUM"])  return TerracottaDifficultyMedium;
    if ([s isEqualToString:@"TOUGH"])   return TerracottaDifficultyTough;
    return TerracottaDifficultyUnknown;
}

- (NSArray<TerracottaProfile *> *)parseProfiles:(id)raw {
    if (![raw isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *d in (NSArray *)raw) {
        TerracottaProfile *p = [TerracottaProfile new];
        p.machineId = d[@"machine_id"] ?: @"";
        p.name      = d[@"name"]        ?: @"";
        p.vendor    = d[@"vendor"]      ?: @"";
        p.kind      = d[@"kind"]        ?: @"";
        [out addObject:p];
    }
    return out;
}

@end
