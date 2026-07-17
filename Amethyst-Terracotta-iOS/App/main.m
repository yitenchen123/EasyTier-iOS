//
//  main.m
//  TerracottaHelper
//
//  Entry point for the standalone Terracotta (陶瓦联机) helper app.
//  This app runs alongside Amethyst-iOS (official or MyRemastered) and
//  provides the EasyTier virtual network layer — Amethyst-iOS itself
//  does NOT need to be modified.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil,
                                 NSStringFromClass([AppDelegate class]));
    }
}
