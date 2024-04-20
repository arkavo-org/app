#include <vector>
#include <string>
#import <Foundation/Foundation.h>
#include "tdf_client.h"
#include "OpenTDFWrapper.h"

const std::string kas_domain = "https://arkavo.net/kas";
const std::string username = "myuser";
const std::string client_key_file = "clientKeyFileName";
const std::string client_cert_file = "clientCertFileName";
const std::string cert_authority = "CertAuthority";

@implementation OpenTDFWrapper : NSObject
- (void)client {
    // Test KAS endpoint - curl https://arkavo.net/kas/v2/kas_public_key
    auto client = virtru::TDFClient(kas_domain, username, client_key_file, client_cert_file, cert_authority);
    std::vector<std::string> testVector;
    testVector.push_back("Hello");
    testVector.push_back("World");
    bool isTDF = client.isStringTDF("not_a_string_tdf");
    testVector.push_back( isTDF ? "true" : "false" );
    for (const std::string& word : testVector) {
        NSLog(@"%s", word.c_str());
    }
}
@end
