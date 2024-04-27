//
//  OpenTDFWrapper.h
//  Arkavo
//
//  Created by Paul Flynn on 4/18/24.
//
#ifndef OpenTDFWrapper_h
#define OpenTDFWrapper_h
#import "Foundation/Foundation.h"

@interface OpenTDFWrapper : NSObject
- (NSData *)encrypt:(NSString *)input;
- (NSString *)decrypt:(NSData *)input;
@end

#endif /* OpenTDFWrapper_h */
