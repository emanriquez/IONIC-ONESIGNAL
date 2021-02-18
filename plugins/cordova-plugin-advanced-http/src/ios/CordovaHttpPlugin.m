#import "CordovaHttpPlugin.h"
#import "CDVFile.h"
#import "BinaryRequestSerializer.h"
#import "BinaryResponseSerializer.h"
#import "TextResponseSerializer.h"
#import "TextRequestSerializer.h"
#import "AFHTTPSessionManager.h"
#import "SDNetworkActivityIndicator.h"

@interface CordovaHttpPlugin()

- (void)setRequestHeaders:(NSDictionary*)headers forManager:(AFHTTPSessionManager*)manager;
- (void)handleSuccess:(NSMutableDictionary*)dictionary withResponse:(NSHTTPURLResponse*)response andData:(id)data;
- (void)handleError:(NSMutableDictionary*)dictionary withResponse:(NSHTTPURLResponse*)response error:(NSError*)error;
- (NSNumber*)getStatusCode:(NSError*) error;
- (NSMutableDictionary*)copyHeaderFields:(NSDictionary*)headerFields;
- (void)setTimeout:(NSTimeInterval)timeout forManager:(AFHTTPSessionManager*)manager;
- (void)setRedirect:(bool)redirect forManager:(AFHTTPSessionManager*)manager;

@end

@implementation CordovaHttpPlugin {
    AFSecurityPolicy *securityPolicy;
    NSURLCredential *x509Credential;
}

- (void)pluginInitialize {
    securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeNone];
}

- (void)setRequestSerializer:(NSString*)serializerName forManager:(AFHTTPSessionManager*)manager {
    if ([serializerName isEqualToString:@"json"]) {
        manager.requestSerializer = [AFJSONRequestSerializer serializer];
    } else if ([serializerName isEqualToString:@"utf8"]) {
        manager.requestSerializer = [TextRequestSerializer serializer];
    } else if ([serializerName isEqualToString:@"raw"]) {
        manager.requestSerializer = [BinaryRequestSerializer serializer];
    } else {
        manager.requestSerializer = [AFHTTPRequestSerializer serializer];
    }
}

- (void)setupAuthChallengeBlock:(AFHTTPSessionManager*)manager {
    [manager setSessionDidReceiveAuthenticationChallengeBlock:^NSURLSessionAuthChallengeDisposition(
        NSURLSession * _Nonnull session,
        NSURLAuthenticationChallenge * _Nonnull challenge,
        NSURLCredential * _Nullable __autoreleasing * _Nullable credential
    ) {
        if ([challenge.protectionSpace.authenticationMethod isEqualToString: NSURLAuthenticationMethodServerTrust]) {
            *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];

            if (![self->securityPolicy evaluateServerTrust:challenge.protectionSpace.serverTrust forDomain:challenge.protectionSpace.host]) {
                return NSURLSessionAuthChallengeRejectProtectionSpace;
            }
            
            if (credential) {
                return NSURLSessionAuthChallengeUseCredential;
            }
        }

        if ([challenge.protectionSpace.authenticationMethod isEqualToString: NSURLAuthenticationMethodClientCertificate] && self->x509Credential) {
            *credential = self->x509Credential;
            return NSURLSessionAuthChallengeUseCredential;
        }
        
        return NSURLSessionAuthChallengePerformDefaultHandling;
    }];
}

- (void)setRequestHeaders:(NSDictionary*)headers forManager:(AFHTTPSessionManager*)manager {
    [headers enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [manager.requestSerializer setValue:obj forHTTPHeaderField:key];
    }];
}

- (void)setRedirect:(bool)followRedirect forManager:(AFHTTPSessionManager*)manager {
    [manager setTaskWillPerformHTTPRedirectionBlock:^NSURLRequest * _Nonnull(NSURLSession * _Nonnull session,
        NSURLSessionTask * _Nonnull task, NSURLResponse * _Nonnull response, NSURLRequest * _Nonnull request) {

        if (followRedirect) {
            return request;
        } else {
            return nil;
        }
    }];
}

- (void)setTimeout:(NSTimeInterval)timeout forManager:(AFHTTPSessionManager*)manager {
    [manager.requestSerializer setTimeoutInterval:timeout];
}

- (void)setResponseSerializer:(NSString*)responseType forManager:(AFHTTPSessionManager*)manager {
    if ([responseType isEqualToString: @"text"] || [responseType isEqualToString: @"json"]) {
        manager.responseSerializer = [TextResponseSerializer serializer];
    } else {
        manager.responseSerializer = [BinaryResponseSerializer serializer];
    }
}


- (void)handleSuccess:(NSMutableDictionary*)dictionary withResponse:(NSHTTPURLResponse*)response andData:(id)data {
    if (response != nil) {
        [dictionary setValue:response.URL.absoluteString forKey:@"url"];
        [dictionary setObject:[NSNumber numberWithInt:(int)response.statusCode] forKey:@"status"];
        [dictionary setObject:[self copyHeaderFields:response.allHeaderFields] forKey:@"headers"];
    }

    if (data != nil) {
        [dictionary setObject:data forKey:@"data"];
    }
}

- (void)handleError:(NSMutableDictionary*)dictionary withResponse:(NSHTTPURLResponse*)response error:(NSError*)error {
    if (response != nil) {
        [dictionary setValue:response.URL.absoluteString forKey:@"url"];
        [dictionary setObject:[NSNumber numberWithInt:(int)response.statusCode] forKey:@"status"];
        [dictionary setObject:[self copyHeaderFields:response.allHeaderFields] forKey:@"headers"];
    } else {
        [dictionary setObject:[self getStatusCode:error] forKey:@"status"];
        [dictionary setObject:[error localizedDescription] forKey:@"error"];
    }
}

- (void)handleException:(NSException*)exception withCommand:(CDVInvokedUrlCommand*)command {
  CordovaHttpPlugin* __weak weakSelf = self;

  NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
  [dictionary setValue:exception.userInfo forKey:@"error"];
  [dictionary setObject:[NSNumber numberWithInt:-1] forKey:@"status"];

  CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dictionary];
  [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (NSNumber*)getStatusCode:(NSError*) error {
    switch ([error code]) {
        case -1001:
            // timeout
            return [NSNumber numberWithInt:-4];
        case -1002:
            // unsupported URL
            return [NSNumber numberWithInt:-5];
        case -1003:
            // server not found
            return [NSNumber numberWithInt:-3];
        case -1009:
            // no connection
            return [NSNumber numberWithInt:-6];
        case -1200: // secure connection failed
        case -1201: // certificate has bad date
        case -1202: // certificate untrusted
        case -1203: // certificate has unknown root
        case -1204: // certificate is not yet valid
            // configuring SSL failed
            return [NSNumber numberWithInt:-2];
        default:
            return [NSNumber numberWithInt:-1];
    }
}

- (NSMutableDictionary*)copyHeaderFields:(NSDictionary *)headerFields {
    NSMutableDictionary *headerFieldsCopy = [[NSMutableDictionary alloc] initWithCapacity:headerFields.count];
    NSString *headerKeyCopy;

    for (NSString *headerKey in headerFields.allKeys) {
        headerKeyCopy = [[headerKey mutableCopy] lowercaseString];
        [headerFieldsCopy setValue:[headerFields objectForKey:headerKey] forKey:headerKeyCopy];
    }

    return headerFieldsCopy;
}

- (void)executeRequestWithoutData:(CDVInvokedUrlCommand*)command withMethod:(NSString*) method {
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];

    NSString *url = [command.arguments objectAtIndex:0];
    NSDictionary *headers = [command.arguments objectAtIndex:1];
    NSTimeInterval timeoutInSeconds = [[command.arguments objectAtIndex:2] doubleValue];
    bool followRedirect = [[command.arguments objectAtIndex:3] boolValue];
    NSString *responseType = [command.arguments objectAtIndex:4];

    [self setRequestSerializer: @"default" forManager: manager];
    [self setupAuthChallengeBlock: manager];
    [self setRequestHeaders: headers forManager: manager];
    [self setTimeout:timeoutInSeconds forManager:manager];
    [self setRedirect:followRedirect forManager:manager];
    [self setResponseSerializer:responseType forManager:manager];

    CordovaHttpPlugin* __weak weakSelf = self;
    [[SDNetworkActivityIndicator sharedActivityIndicator] startActivity];

    @try {
        void (^onSuccess)(NSURLSessionTask *, id) = ^(NSURLSessionTask *task, id responseObject) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            
            // no 'body' for HEAD request, omitting 'data'
            if ([method isEqualToString:@"HEAD"]) {
                [self handleSuccess:dictionary withResponse:(NSHTTPURLResponse*)task.response andData:nil];
            } else {
                [self handleSuccess:dictionary withResponse:(NSHTTPURLResponse*)task.response andData:responseObject];
            }
            
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            [[SDNetworkActivityIndicator sharedActivityIndicator] stopActivity];
        };
        
        void (^onFailure)(NSURLSessionTask *, NSError *) = ^(NSURLSessionTask *task, NSError *error) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleError:dictionary withResponse:(NSHTTPURLResponse*)task.response error:error];
            
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            [[SDNetworkActivityIndicator sharedActivityIndicator] stopActivity];
        };
        
        NSURLSessionDataTask *dataTask = [manager dataTaskWithHTTPMethod:method URLString:url parameters:nil headers:nil uploadProgress:^(NSProgress * _Nonnull uploadProgress) {
            
        } downloadProgress:^(NSProgress * _Nonnull downloadProgress) {
            
        } success:onSuccess failure:onFailure];
        [dataTask resume];
    }
    @catch (NSException *exception) {
        [[SDNetworkActivityIndicator sharedActivityIndicator] stopActivity];
        [self handleException:exception withCommand:command];
    }
}

- (void)executeRequestWithData:(CDVInvokedUrlCommand*)command withMethod:(NSString*)method {
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];

    NSString *url = [command.arguments objectAtIndex:0];
    NSDictionary *data = [command.arguments objectAtIndex:1];
    NSString *serializerName = [command.arguments objectAtIndex:2];
    NSDictionary *headers = [command.arguments objectAtIndex:3];
    NSTimeInterval timeoutInSeconds = [[command.arguments objectAtIndex:4] doubleValue];
    bool followRedirect = [[command.arguments objectAtIndex:5] boolValue];
    NSString *responseType = [command.arguments objectAtIndex:6];

    [self setRequestSerializer: serializerName forManager: manager];
    [self setupAuthChallengeBlock: manager];
    [self setRequestHeaders: headers forManager: manager];
    [self setTimeout:timeoutInSeconds forManager:manager];
    [self setRedirect:followRedirect forManager:manager];
    [self setResponseSerializer:responseType forManager:manager];

    CordovaHttpPlugin* __weak weakSelf = self;
    [[SDNetworkActivityIndicator sharedActivityIndicator] startActivity];
    
    @try {
        
        void (^onSuccess)(NSURLSessionTask *, id) = ^(NSURLSessionTask *task, id responseObject) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleSuccess:dictionary withResponse:(NSHTTPURLResponse*)task.response andData:responseObject];
            
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            [[SDNetworkActivityIndicator sharedActivityIndicator] stopActivity];
        };
        
        void (^onFailure)(NSURLSessionTask *, NSError *) = ^(NSURLSessionTask *task, NSError *error) {
            NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
            [self handleError:dictionary withResponse:(NSHTTPURLResponse*)task.response error:error];
            
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:dictionary];
            [weakSelf.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            [[SDNetworkActivityIndicator sharedActivityIndicator] stopActivity];
        };
        
        NSURLSessionDataTask *dataTask = [manager dataTaskWithHTTPMethod:method URLString:url parameters:data headers:nil uploadProgress:^(NSProgress * _Nonnull uploadProgress) {
            
        } downloadProgress:^(NSProgress * _Nonnull downloadProgress) {
            
        } success:onSuccess failure:onFailure];
        [dataTask resume];
    }
    @catch (NSException *exception) {
        [[SDNetworkActivityIndicator sharedActivityIndicator] stopActivity];
        [self handleException:exception withCommand:command];
    }
}

- (void)setServerTrustMode:(CDVInvokedUrlCommand*)command {
    NSString *certMode = [command.arguments objectAtIndex:0];

    if ([certMode isEqualToString: @"default"] || [certMode isEqualToString: @"legacy"]) {
        securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeNone];
        securityPolicy.allowInvalidCertificates = NO;
        securityPolicy.validatesDomainName = YES;
    } else if ([certMode isEqualToString: @"nocheck"]) {
        securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeNone];
        securityPolicy.allowInvalidCertificates = YES;
        securityPolicy.validatesDomainName = NO;
    } else if ([certMode isEqualToString: @"pinned"]) {
        securityPolicy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeCertificate];
        securityPolicy.allowInvalidCertificates = NO;
        securityPolicy.validatesDomainName = YES;
    }

    CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)setClientAuthMode:(CDVInvokedUrlCommand*)command {
    CDVPluginResult* pluginResult;
    NSString *mode = [command.arguments objectAtIndex:0];
    
    if ([mode isEqualToString:@"none"]) {
      x509Credential = nil;
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    }
  
    if ([mode isEqualToString:@"systemstore"]) {
      // TODO
      
      pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"mode 'systemstore' is not supported on iOS"];
    }
  
    if ([mode isEqualToString:@"buffer"]) {
        CFDataRef container = (__bridge CFDataRef) [command.arguments objectAtIndex:2];
        CFStringRef password = (__bridge CFStringRef) [command.arguments objectAtIndex:3];
      
        const void *keys[] = { kSecImportExportPassphrase };
        const void *values[] = { password };
      
        CFDictionaryRef options = CFDictionaryCreate(NULL, keys, values, 1, NULL, NULL);
        CFArrayRef items;
        OSStatus securityError = SecPKCS12Import(container, options, &items);
        CFRelease(options);

        if (securityError != noErr) {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
        } else {
            CFDictionaryRef identityDict = CFArrayGetValueAtIndex(items, 0);
            SecIdentityRef identity = (SecIdentityRef)CFDictionaryGetValue(identityDict, kSecImportItemIdentity);

            self->x509Credential = [NSURLCredential credentialWithIdentity:identity certificates: nil persistence:NSURLCredentialPersistenceForSession];
            CFRelease(items);
          
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        }
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)post:(CDVInvokedUrlCommand*)command {
    [self executeRequestWithData: command withMethod:@"POST"];
}

- (void)put:(CDVInvokedUrlCommand*)command {
    [self executeRequestWithData: command withMethod:@"PUT"];
}

- (void)patch:(CDVInvokedUrlCommand*)command {
    [self executeRequestWithData: command withMethod:@"PATCH"];
}

- (void)get:(CDVInvokedUrlCommand*)command {
    [self executeRequestWithoutData: command withMethod:@"GET"];
}

- (void)delete:(CDVInvokedUrlCommand*)command {
    [self executeRequestWithoutData: command withMethod:@"DELETE"];
}

- (void)head:(CDVInvokedUrlCommand*)command {
    [self executeRequestWithoutData: command withMethod:@"HEAD"];
}

- (void)options:(CDVInvokedUrlCommand*)command {
    [self executeRequestWithoutData: command withMethod:@"OPTIONS"];
}

@end
