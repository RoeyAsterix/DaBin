// Test-only warning call stacks in a single owned QA process. Never linked
// into DaBin, never hides/replaces the original diagnostic text.
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>

static void traceWarning(NSString *format, va_list arguments) {
    va_list copy; va_copy(copy, arguments);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:copy];
    va_end(copy);
    if ([message containsString:@"reentrant operation in its NSTableView delegate"]) {
        fprintf(stderr, "DABIN_QA_WARNING_STACK_BEGIN\n%s\n%s\nDABIN_QA_WARNING_STACK_END\n",
                message.UTF8String, [NSThread.callStackSymbols componentsJoinedByString:@"\n"].UTF8String);
    }
}
static void tracedNSLog(NSString *format, ...) {
    va_list arguments; va_start(arguments, format);
    traceWarning(format, arguments);
    NSLogv(format, arguments); va_end(arguments);
}
__attribute__((used)) static struct { const void *replacement; const void *replacee; }
    interposers[] __attribute__((section("__DATA,__interpose"))) = {
        { (const void *)tracedNSLog, (const void *)NSLog }
    };
