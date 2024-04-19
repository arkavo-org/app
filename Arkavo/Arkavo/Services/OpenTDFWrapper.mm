#include <vector>
#include <string>
#import <Foundation/Foundation.h>
#include "tdf_client.h"
#include "OpenTDFWrapper.h"

@implementation OpenTDFWrapper : NSObject
- (void)exampleMethod {
//    curl https://arkavo.net/kas/v2/kas_public_key
    virtru::TDFClient("https://arkavo.net/kas", "myuser", "clientKeyFileName", "clientCertFileName", "sdkConsumerCertAuthority");
    std::vector<std::string> testVector;
    testVector.push_back("Goodbye");
    testVector.push_back("World");

    for (const std::string& word : testVector) {
        NSLog(@"%s", word.c_str());
    }
}
@end
