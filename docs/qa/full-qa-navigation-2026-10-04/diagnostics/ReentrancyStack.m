#import <Foundation/Foundation.h>
#import <stdarg.h>
#include <stdio.h>

// Diagnostic-only interposition in an isolated QA executable, never shipped.
static void diagnosticNSLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    va_list copy;
    va_copy(copy, args);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:copy];
    va_end(copy);
    static BOOL reported = NO;
    if (!reported && [message containsString:@"reentrant operation in its NSTableView"]) {
        reported = YES;
        NSString *stack = [[NSThread callStackSymbols] componentsJoinedByString:@"\n"];
        fprintf(stderr, "QA DIAGNOSTIC: %s\n%s\n", message.UTF8String, stack.UTF8String);
    }
    NSLogv(format, args);
    va_end(args);
}
__attribute__((used)) static struct { const void *replacement; const void *original; }
interpose __attribute__((section("__DATA,__interpose"))) = {
    (const void *)diagnosticNSLog, (const void *)NSLog
};
