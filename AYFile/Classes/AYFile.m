//
//  AYFile.m
//  AYFile
//
//  Created by Alan Yeh on 16/7/22.
//
//

#import "AYFile.h"
#include <CommonCrypto/CommonDigest.h>
#import <SSZipArchive/SSZipArchive.h>

NSString * const AYFileErrorDomain = @"cn.yerl.error.AYFile";
NSString * const AYFileErrorKey = @"cn.yerl.error.AYFile.error.key";

@interface AYFile ()
@property (nonatomic, retain) NSFileManager *manager;
@property (nonatomic, retain) NSDictionary *attributes;
@end

@implementation AYFile{
    NSError *_lastError;
    NSString *_path;
}

+ (AYFile *)fileWithPath:(NSString *)path{
    return [[AYFile alloc] initWithPath:path];
}

+ (AYFile *)fileWithURL:(NSURL *)url{
    if (url == nil) {
        return nil;
    }
    // 不支持非file://协议的URL
    if (![url.scheme isEqualToString:@"file"]) {
        return nil;
    }
    return [[AYFile alloc] initWithPath:url.path];
}

- (instancetype)initWithPath:(NSString *)path{
    if (path.length < 1) {
        return nil;
    }
    if (self = [super init]) {
        _path = [path stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // 超出沙盒的路径不支持
        if (![_path isEqualToString:NSHomeDirectory()] && [NSHomeDirectory() rangeOfString:_path].location != NSNotFound) {
            return nil;
        }
        _manager = [NSFileManager new];
        [_manager changeCurrentDirectoryPath:path];
    }
    return self;
}

#pragma mark - 状态
- (NSString *)path{
    return _path;
}

- (NSURL *)url{
    return [NSURL fileURLWithPath:_path];
}

- (NSString *)name{
    return [self.path lastPathComponent];;
}

- (NSString *)simpleName{
    return [[self.path lastPathComponent] stringByDeletingPathExtension];
}

- (NSString *)extension{
    return [[self.path lastPathComponent] pathExtension];
}

- (BOOL)isDirectory{
    BOOL isDirectory;
    [_manager fileExistsAtPath:_path isDirectory:&isDirectory];
    return isDirectory;
}

- (BOOL)isFile{
    return !self.isDirectory;
}

- (BOOL)isExists{
    return [_manager fileExistsAtPath:_path isDirectory:nil];
}

- (BOOL)hasParent{
    NSString *parentPath = [_path stringByDeletingLastPathComponent];
    return !([parentPath isEqualToString:NSHomeDirectory()] && [NSHomeDirectory() rangeOfString:parentPath].location != NSNotFound);
}

- (NSString *)md5{
    if (!self.isExists) {
        return nil;
    }
    if (self.isDirectory) {
        return nil;
    }
    
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:self.path];
    
    CC_MD5_CTX MD5_CTX;
    CC_MD5_Init(&MD5_CTX);
    
    BOOL done = NO;
    while (!done) {
        NSData *fileData = [handle readDataOfLength:1024];
        CC_MD5_Update(&MD5_CTX, fileData.bytes, (uint32_t)fileData.length);
        done = fileData.length < 1024;
    }
    
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5_Final(digest, &MD5_CTX);
    NSMutableString *result = [NSMutableString new];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i ++) {
        [result appendFormat:@"%02x", digest[i]];
    }
    return result.copy;
}

- (BOOL)delete{
    if (self.isExists) {
        NSError *error = nil;
        BOOL result = [_manager removeItemAtPath:_path error:&error];
        _lastError = error;
        _log_error(_lastError, _cmd);
        return result;
    }
    return YES;
}

- (BOOL)clear{
    if (self.isExists) {
        NSError *error = nil;
        BOOL isDirector = self.isDirectory;
        BOOL result = [_manager removeItemAtPath:_path error:&error];
        _lastError = error;
        _log_error(error, _cmd);
        if (error == nil && isDirector) {
            [self makeDirs];
        }
        return result;
    }
    return YES;
}

- (long long)size{
    if (self.isFile) {
        return self.attributes.fileSize;
    }else{
        long long size =0;
        for (AYFile *child in self.children) {
            size += child.size;
        }
        return size;
    }
}

- (NSTimeInterval)modificationDate{
    return self.attributes.fileModificationDate.timeIntervalSince1970;
}

- (NSTimeInterval)creationDate{
    return self.attributes.fileCreationDate.timeIntervalSince1970;
}

- (nullable NSDictionary<NSFileAttributeKey, id> *)attributes{
    if (!_attributes) {
        _attributes = [_manager attributesOfItemAtPath:_path error:nil];
    }
    return _attributes;
}

#pragma mark - 进入/返回文件夹
- (AYFile *)root{
    return [AYFile home];
}

- (AYFile *)parent{
    NSString *parentPath = [_path stringByDeletingLastPathComponent];
    //判断是否超出沙盒
    if (![parentPath isEqualToString:NSHomeDirectory()] && [NSHomeDirectory() rangeOfString:parentPath].location != NSNotFound) {
        return nil;
    }
    return [AYFile fileWithPath:parentPath];
}

- (AYFile *)child:(NSString *)name{
    return [AYFile fileWithPath:[_path stringByAppendingPathComponent:name]];
}

- (NSArray<AYFile *> *)children{
    NSError *error = nil;
    NSArray<NSString *> *directories = [_manager contentsOfDirectoryAtPath:_path error:&error];
    if (error) {
        
        return nil;
    }
    
    NSMutableArray<AYFile *> *files = [NSMutableArray new];
    [directories enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [files addObject:[[AYFile alloc] initWithPath:[_path stringByAppendingPathComponent:obj]]];
    }];
    
    return files;
}

#pragma mark - 读取与写入
- (BOOL)makeDirs{
    if (self.isExists) {
        return YES;
    }else{
        NSError *error = nil;
        BOOL result = [_manager createDirectoryAtPath:_path
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:&error];
        _lastError = error;
        _log_error(_lastError, _cmd);
        
        return result;
    }
}

- (NSData *)data{
    return [NSData dataWithContentsOfFile:_path];
}

- (NSString *)text{
    return [NSString stringWithContentsOfFile:self.path encoding:NSUTF8StringEncoding error:nil];
}

- (NSString *)textWithEncoding:(NSStringEncoding)encoding{
    return [NSString stringWithContentsOfFile:self.path encoding:encoding error:nil];
}

- (void)writeData:(NSData *)data{
    if (self.isExists) {
        [self delete];
    }
    [data writeToFile:self.path atomically:YES];
}

- (void)writeText:(NSString *)text{
    [self writeData:[text dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)writeText:(NSString *)text withEncoding:(NSStringEncoding)encoding{
    [self writeData:[text dataUsingEncoding:encoding]];
}

- (void)appendData:(NSData *)data{
    if (!self.isExists) {
        [self writeData:data];
    }else{
        NSFileHandle *handle = [NSFileHandle fileHandleForUpdatingAtPath:self.path];
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    }
}

- (void)appendText:(NSString *)text{
    [self appendData:[text dataUsingEncoding:NSUTF8StringEncoding]];
}

- (void)appendText:(NSString *)text withEncoding:(NSStringEncoding)encoding{
    [self appendData:[text dataUsingEncoding:encoding]];
}

- (AYFile *)write:(NSData *)data withName:(NSString *)name{
    NSParameterAssert(name.length > 0);
    [self makeDirs];
    
    data = data ?: [NSData data];
    
    AYFile *target = [self child:name];
    [data writeToFile:target.path atomically:YES];
    return target;
}

- (BOOL)copyToPath:(AYFile *)newFile{
    NSParameterAssert(newFile != nil);
    
    if ([self isEqualToFile:newFile]) {
        return YES;
    }
    
    if (!self.isExists) {
        _lastError = [NSError errorWithDomain:AYFileErrorDomain code:-1001 userInfo:@{AYFileErrorKey: [NSString stringWithFormat:@"Source file in path <%@> is not exists.", self.path]}];
        _log_error(_lastError, _cmd);
        return NO;
    }
    
    [[newFile parent] makeDirs];
    
    if (self.isDirectory) {
        NSArray<AYFile *> *children = self.children;
        BOOL result = YES;
        if (children.count < 1) {
            // 如果没有子文件（夹），就直接在目标上创建文件夹就好
            result = [newFile makeDirs];
        }else{
            for (AYFile *file in children) {
                if (!result) {
                    return result;
                }
                result  = [file copyToPath:[newFile child: file.name]];
            }
        }
        return result;
    }else{
        // 移动文件
        NSError *error = nil;
        BOOL result = [_manager copyItemAtPath:self.path toPath:newFile.path error:&error];
        _lastError = error;
        _log_error(_lastError, _cmd);
        return result;
    }
}

- (BOOL)moveToPath:(AYFile *)newFile{
    BOOL result = [self copyToPath:newFile];
    if (result) {
        [self delete];
    }
    return result;
}

#pragma mark - orverride
- (NSString *)description{
    return [NSString stringWithFormat:@"\n<AYFile: %p>:\n{\n   type: %@,\n   path: %@\n}", self, self.isDirectory ? @"Directory" : @"File", _path];
}

- (NSString *)debugDescription{
    return [NSString stringWithFormat:@"\n<AYFile: %p>:\n{\n   type: %@,\n   path: %@\n}", self, self.isDirectory ? @"Directory" : @"File", _path];
}

- (BOOL)isEqualToFile:(AYFile *)otherFile{
    return [self.path isEqualToString:otherFile.path];
}

static void _log_error(NSError *error, SEL selector){
    if (error) {
        NSLog(@"\n⚠️⚠️WARNING: \n  An error occured when execute selector [- %@]:\n%@", NSStringFromSelector(selector) , error);
    }
}

@end

@implementation AYFile (Zip)
- (AYFile *)zip{
    return [self zipToPath:[[self parent] child:[self.simpleName stringByAppendingPathExtension:@"zip"]] withPassword:nil];
}

- (AYFile *)zipWithPassword:(NSString *)password{
    return [self zipToPath:[[self parent] child:[self.simpleName stringByAppendingPathExtension:@"zip"]] withPassword:password];
}

- (AYFile *)zipToPath:(AYFile *)file{
    return [self zipToPath:file withPassword:nil];
}

- (AYFile *)zipToPath:(AYFile *)file withPassword:(NSString *)password{
    [file.parent makeDirs];
    
    if (self.isDirectory) {
        BOOL res = [SSZipArchive createZipFileAtPath:file.path withContentsOfDirectory:self.path keepParentDirectory:YES withPassword:password];
        return res ? file : nil;
    }else {
        BOOL res = [SSZipArchive createZipFileAtPath:file.path withFilesAtPaths:@[self.path] withPassword:password];
        return res ? file : nil;
    }
}

- (AYFile *)unZip{
    return [self unZipToPath:[[self parent] child:self.simpleName] withPassword:nil];
}

- (AYFile *)unZipWithPassword:(NSString *)password{
    return [self unZipToPath:[[self parent] child:self.simpleName] withPassword:password];
}

- (AYFile *)unZipToPath:(AYFile *)file{
    return [self unZipToPath:file withPassword:nil];
}

- (AYFile *)unZipToPath:(AYFile *)file withPassword:(NSString *)password{\
    if (!file) {
        _lastError = [NSError errorWithDomain:AYFileErrorDomain code:-1001 userInfo:@{
                                                                                      NSLocalizedDescriptionKey: @"目标文件夹不能为空"
                                                                                      }];
        _log_error(_lastError, _cmd);
        return nil;
    }
    
    if (file.isExists && file.isFile) {
        _lastError = [NSError errorWithDomain:AYFileErrorDomain code:-1001 userInfo:@{
                                                                                      NSLocalizedDescriptionKey: @"只能解压到文件夹"
                                                                                      }];
        _log_error(_lastError, _cmd);
        return nil;
    }
    
    if (!self.isFile || ![self.extension isEqualToString:@"zip"]) {
        _lastError = [NSError errorWithDomain:AYFileErrorDomain code:-1001 userInfo:@{
                                                                                      NSLocalizedDescriptionKey: @"待解压文件不是有效的压缩文件"
                                                                                      }];
        _log_error(_lastError, _cmd);
        return nil;
    }
    
    [file makeDirs];
    
    NSError *error;
    BOOL res = [SSZipArchive unzipFileAtPath:self.path toDestination:file.path overwrite:YES password:password error:&error];
    
    _lastError = error;
    _log_error(error, _cmd);

    return res ? file : nil;
}
@end

@implementation AYFile (Directory)
+ (AYFile *)home{
    return [AYFile fileWithPath:NSHomeDirectory()];
}

+ (AYFile *)caches{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachesDir = [paths objectAtIndex:0];
    return [AYFile fileWithPath:cachesDir];
}

+ (AYFile *)documents{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = [paths objectAtIndex:0];
    return [AYFile fileWithPath:docDir];
}

+ (AYFile *)tmp{
    return [AYFile fileWithPath:NSTemporaryDirectory()];
}
@end
