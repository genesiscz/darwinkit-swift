#import "DarwinKitObjC.h"

NSString * const DarwinKitObjCExceptionDomain = @"DarwinKitObjCException";
NSString * const DarwinKitObjCExceptionNameKey = @"NSExceptionName";
NSString * const DarwinKitObjCExceptionReasonKey = @"NSExceptionReason";

@implementation DarwinKitObjC

+ (BOOL)catchException:(NS_NOESCAPE void (^)(void))block
                 error:(NSError *__autoreleasing _Nullable *_Nullable)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSString *name = exception.name ?: @"NSException";
            NSString *reason = exception.reason ?: @"";
            NSDictionary *userInfo = @{
                NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@: %@", name, reason],
                DarwinKitObjCExceptionNameKey: name,
                DarwinKitObjCExceptionReasonKey: reason,
            };
            *error = [NSError errorWithDomain:DarwinKitObjCExceptionDomain
                                         code:-1
                                     userInfo:userInfo];
        }
        return NO;
    }
}

@end
