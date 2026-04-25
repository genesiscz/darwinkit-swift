#ifndef DarwinKitObjC_h
#define DarwinKitObjC_h

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString * const DarwinKitObjCExceptionDomain;
extern NSString * const DarwinKitObjCExceptionNameKey;
extern NSString * const DarwinKitObjCExceptionReasonKey;

@interface DarwinKitObjC : NSObject

// Catches Objective-C exceptions raised inside the block. The block must be
// fail-fast: callers must not carry Swift state across the boundary, since
// Swift unwinding through @catch is technically undefined behavior. Treat
// the failed work as fully aborted (drop the request, move on).
+ (BOOL)catchException:(NS_NOESCAPE void (^)(void))block
                 error:(NSError *__autoreleasing _Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END

#endif
