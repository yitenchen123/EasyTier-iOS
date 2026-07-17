//
//  TerracottaLog.m
//  Amethyst
//

#import "TerracottaLog.h"
#import <os/log.h>

void TerracottaLogWrite(NSString *level, NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    static os_log_t logger = NULL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        logger = os_log_create("org.angelauramc.amethyst", "Terracotta");
    });

    os_log_type_t type = OS_LOG_TYPE_DEFAULT;
    if ([level isEqualToString:@"ERROR"]) type = OS_LOG_TYPE_ERROR;
    else if ([level isEqualToString:@"WARN"]) type = OS_LOG_TYPE_INFO;
    else if ([level isEqualToString:@"INFO"]) type = OS_LOG_TYPE_INFO;
    else if ([level isEqualToString:@"DEBUG"]) type = OS_LOG_TYPE_DEBUG;
    else if ([level isEqualToString:@"VERBOSE"]) type = OS_LOG_TYPE_DEBUG;

    os_log_with_type(logger, type, "%{public}s",
                     [message cStringUsingEncoding:NSUTF8StringEncoding] ?: "");

    // Also NSLog for easy copy-paste from Xcode console during development.
    NSLog(@"[Terracotta/%@] %@", level, message);
}
