#include <vector>
#include <string>
#import <Foundation/Foundation.h>
#include <iostream>
#include <stdexcept>
#include "tdf_client.h"
#include "nanotdf_client.h"
#include "OpenTDFWrapper.h"
#include "tdf_exception.h"

// Test KAS - curl https://arkavo.net/kas/v2/kas_public_key
const std::string kas_domain = "https://platform.virtru.us/api/kas"; // https://arkavo.net/kas | https://platform.virtru.us/api/kas
// Test WebAuthn - curl https://webauthn.arkavo.net/generate-registration-options
const std::string oidc_endpoint = "https://webauthn.arkavo.net"; // https://webauthn.arkavo.net | https://platform.virtru.us
const std::string client_id = "tdf-client";
const std::string client_secret="123-456";
const std::string organization_name = "tdf";

@interface OpenTDFWrapper ()
@property(nonatomic) virtru::NanoTDFClient *tdfClient;
@end

@implementation OpenTDFWrapper : NSObject

- (id)init {
    self = [super init];
    if (!self.tdfClient) {
        NSLog(@"%s", "init");
        virtru::OIDCCredentials oidcCreds;
        oidcCreds.setClientCredentialsClientSecret(client_id, client_secret, organization_name, oidc_endpoint);
        // allocate new TDFClient
        try {
            _tdfClient = new virtru::NanoTDFClient(oidcCreds, kas_domain);
            _tdfClient->enableBenchmark();
//            _tdfClient->enableConsoleLogging(virtru::LogLevel::Trace);
        } catch (const std::runtime_error& e) {
            std::cout << "Caught a std::runtime_error: " << e.what() << std::endl;
        } catch (...) {
            std::cout << "Caught an unspecified exception" << std::endl;
        }
    }
    return self;
}

- (NSData *)encrypt:(NSString *)input {
    NSLog(@"%s", "encrypt");
    // create TDF
    virtru::TDFStorageType tdfStorageType;
    std::string cppString = std::string([input UTF8String]);
    tdfStorageType.setTDFStorageStringType(cppString);
    @try {
        try {
            auto mytdf = _tdfClient->encryptData(tdfStorageType);
            return [[NSData alloc] initWithBytes:mytdf.data() length:mytdf.size()];
        } catch (const virtru::Exception& ex) {
            std::cerr << ex.what() << '\n';
            NSLog(@"Exception occurred: %d", ex.code());
        } catch (const std::runtime_error& ex) {
            std::cerr << ex.what() << '\n';
            NSLog(@"Exception occurred: %s", ex.what());
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Exception occurred: %@, %@", exception, [exception userInfo]);
    }
    return nil;
}

- (NSString *)decrypt:(NSData *)input {
    NSLog(@"%s", "decrypt");
    // decrypt TDF
    virtru::TDFStorageType tdfStorageType;
    NSUInteger length = [input length];
    std::vector<virtru::VBYTE> buffer(length);
    memcpy(&buffer[0], [input bytes], length);
    tdfStorageType.setTDFStorageBufferType(buffer);
    @try {
        try {
    auto vectorData = _tdfClient->decryptData(tdfStorageType);
    // Convert std::vector<VBYTE> to NSData
    NSData *data = [NSData dataWithBytes:vectorData.data() length:vectorData.size()];
    // Convert NSData to NSString
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        } catch (const virtru::Exception& ex) {
            std::cerr << ex.what() << '\n';
            NSLog(@"Exception opentdf: %d", ex.code());
            return [NSString stringWithUTF8String:ex.what()];
        } catch (const std::runtime_error& ex) {
            std::cerr << ex.what() << '\n';
            NSLog(@"Exception: %s", ex.what());
            return [NSString stringWithUTF8String:ex.what()];
        }
    }
    @catch (NSException *exception) {
        NSLog(@"Exception occurred: %@, %@", exception, [exception userInfo]);
    }
    return @"nil";
}

@end
