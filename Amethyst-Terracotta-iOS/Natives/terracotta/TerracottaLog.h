//
//  TerracottaLog.h
//  Amethyst
//
//  Lightweight logging macros for the Terracotta module. Forwards to
//  Apple's os_log / NSLog so logs appear in Console.app and Xcode.
//

#ifndef TerracottaLog_h
#define TerracottaLog_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void TerracottaLogWrite(NSString *level, NSString *format, ...);

#ifdef __cplusplus
}
#endif

#define TerracottaLogVerbose(fmt, ...) TerracottaLogWrite(@"VERBOSE", fmt, ##__VA_ARGS__)
#define TerracottaLogDebug(fmt, ...)   TerracottaLogWrite(@"DEBUG",   fmt, ##__VA_ARGS__)
#define TerracottaLogInfo(fmt, ...)    TerracottaLogWrite(@"INFO",    fmt, ##__VA_ARGS__)
#define TerracottaLogWarn(fmt, ...)    TerracottaLogWrite(@"WARN",    fmt, ##__VA_ARGS__)
#define TerracottaLogError(fmt, ...)   TerracottaLogWrite(@"ERROR",   fmt, ##__VA_ARGS__)

#endif /* TerracottaLog_h */
