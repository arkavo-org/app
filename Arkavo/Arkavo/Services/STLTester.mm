#include <vector>
#include <string>
#import <Foundation/Foundation.h>
#import "STLTester.h"

@implementation STLTester

- (void)testSTL {
    std::vector<std::string> testVector;
    testVector.push_back("Hello");
    testVector.push_back("World");

    for (const std::string& word : testVector) {
        NSLog(@"%s", word.c_str());
    }
}

@end
