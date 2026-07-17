//
//  AppDelegate.m
//  TerracottaHelper
//
//  Standalone Terracotta (陶瓦联机) helper app.
//
//  This app provides the EasyTier virtual-network layer that lets
//  Amethyst-iOS (official or MyRemastered — both unmodified) join
//  the same 陶瓦联机 rooms as HMCL / FCL / ZalithLauncher2.
//
//  Key responsibilities of the AppDelegate:
//    1. Initialize the Terracotta Rust engine on launch.
//    2. Start the silent-audio background keep-alive so EasyTier
//       keeps running when the user switches to Amethyst-iOS.
//    3. Set up the root UI (RootViewController).
//

#import "AppDelegate.h"
#import "RootViewController.h"
#import "TerracottaBridge.h"
#import "TerracottaLog.h"
#import "SilentAudioPlayer.h"

@interface AppDelegate ()
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
        didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    // ---- 1. Initialize Terracotta engine ----
    // Use the app's Documents directory as the working directory.
    // A `machine-id` file is created here to persist player identity.
    NSString *docs = [NSSearchPathForDirectoriesInDomains(
                         NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *workDir = [docs stringByAppendingPathComponent:@"terracotta"];
    NSString *logPath = [workDir stringByAppendingPathComponent:@"terracotta.log"];

    // Create the working directory if it doesn't exist.
    [[NSFileManager defaultManager] createDirectoryAtPath:workDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    NSError *err = nil;
    BOOL ok = [[TerracottaBridge shared] startWithWorkingDirectory:workDir
                                                       loggingPath:logPath
                                                             error:&err];
    if (!ok) {
        TerracottaLogError(@"Failed to start Terracotta engine: %@", err);
    } else {
        TerracottaLogInfo(@"Terracotta engine started. workDir=%@", workDir);
    }

    // ---- 2. Start silent-audio background keep-alive ----
    // This is CRITICAL: when the user switches from this app to Amethyst-iOS,
    // iOS will suspend this app unless it has a background mode active.
    // The "audio" background mode with a looping silent audio player keeps
    // the app (and thus EasyTier's networking threads) alive in background.
    [[SilentAudioPlayer shared] start];

    // ---- 3. Set up root UI ----
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = UIColor.systemBackgroundColor;
    self.window.rootViewController = [[UINavigationController alloc]
                               initWithRootViewController:[[RootViewController alloc] init]];
    [self.window makeKeyAndVisible];

    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // The user is switching away (e.g. to Amethyst-iOS).
    // SilentAudioPlayer keeps us alive in background.
    TerracottaLogInfo(@"App resigning active — background keep-alive is on.");
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    TerracottaLogInfo(@"App entered background.");
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    TerracottaLogInfo(@"App entering foreground.");
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    TerracottaLogInfo(@"App became active.");
}

- (void)applicationWillTerminate:(UIApplication *)application {
    TerracottaLogInfo(@"App terminating — cleaning up Terracotta.");
    [[TerracottaBridge shared] setWaiting];
    [[SilentAudioPlayer shared] stop];
}

@end
