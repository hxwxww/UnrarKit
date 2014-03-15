//
//  Unrar4iOS.mm
//  Unrar4iOS
//
//  Created by Rogerio Pereira Araujo on 10/11/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "Unrar4iOS.h"


NSString *URRErrorDomain = @"URRErrorDomain";

@implementation Unrar4iOS

int CALLBACK CallbackProc(UINT msg, long UserData, long P1, long P2) {
	UInt8 **buffer;
	
	switch(msg) {
			
		case UCM_CHANGEVOLUME:
			break;
		case UCM_PROCESSDATA:
			buffer = (UInt8 **) UserData;
			memcpy(*buffer, (UInt8 *)P1, P2);
			// advance the buffer ptr, original m_buffer ptr is untouched
			*buffer += P2;
			break;
		case UCM_NEEDPASSWORD:
			break;
	}
	return(0);
}



#pragma mark - Convenience Methods


+ (Unrar4iOS *)unrarFileAtPath:(NSString *)filePath;
{
    Unrar4iOS *result = [[Unrar4iOS alloc] init];
    [result openFile:filePath];
    
    return [result autorelease];
}

+ (Unrar4iOS *)unrarFileAtURL:(NSURL *)fileURL;
{
    Unrar4iOS *result = [[Unrar4iOS alloc] init];
    [result openFile:fileURL.path];
    
    return [result autorelease];
}

+ (Unrar4iOS *)unrarFileAtPath:(NSString *)filePath password:(NSString *)password;
{
    Unrar4iOS *result = [[Unrar4iOS alloc] init];
    [result openFile:filePath password:password];
    
    return [result autorelease];
}

+ (Unrar4iOS *)unrarFileAtURL:(NSURL *)fileURL password:(NSString *)password;
{
    Unrar4iOS *result = [[Unrar4iOS alloc] init];
    [result openFile:fileURL.path password:password];
    
    return [result autorelease];
}



#pragma mark - Public Methods


- (void)openFile:(NSString *)filePath;
{
	[self openFile:filePath password:nil];
}

- (void)openFile:(NSString *)filePath password:(NSString*)password;
{
	self.filename = filePath;
    self.password = password;
}

- (NSArray *)listFiles:(NSError **)error;
{
	int RHCode = 0, PFCode = 0;
    
	if (![self _unrarOpenFile:_filename
                       inMode:RAR_OM_LIST_INCSPLIT
                 withPassword:_password
                        error:error]) {
        return nil;
    }
	
	NSMutableArray *files = [NSMutableArray array];
	while ((RHCode = RARReadHeaderEx(_rarFile, header)) == 0) {
		NSString *filename = [NSString stringWithCString:header->FileName encoding:NSASCIIStringEncoding];
		[files addObject:filename];
		
		if ((PFCode = RARProcessFile(_rarFile, RAR_SKIP, NULL, NULL)) != 0) {
            [self assignError:error code:(NSInteger)PFCode];
			return nil;
		}
	}
    
	return files;
}

- (BOOL)extractFilesTo:(NSString *)filePath overWrite:(BOOL)overwrite error:(NSError **)error;
{
    int RHCode = 0, PFCode = 0;
    
    if (![self _unrarOpenFile:_filename inMode:RAR_OM_EXTRACT withPassword:_password error:error])
        return NO;
    
	while ((RHCode = RARReadHeaderEx(_rarFile, header)) == 0) {
        
        if ((PFCode = RARProcessFile(_rarFile, RAR_EXTRACT, (char *)[filePath UTF8String], NULL)) != 0) {
            [self assignError:error code:(NSInteger)PFCode];
            return NO;
        }
        
    }
    
    return YES;
}

- (NSData *)extractDataFromFile:(NSString *)filePath error:(NSError **)error;
{
	int RHCode = 0, PFCode = 0;
	
    if (error) {
        *error = nil;
    }
    
	if (![self _unrarOpenFile:_filename
                       inMode:RAR_OM_EXTRACT
                 withPassword:_password
                        error:error]) {
        return nil;
    }
	
	size_t length = 0;
	while ((RHCode = RARReadHeaderEx(_rarFile, header)) == 0) {
		NSString *filename = [NSString stringWithCString:header->FileName encoding:NSASCIIStringEncoding];
        
		if ([filename isEqualToString:filePath]) {
			length = header->UnpSize;
			break;
		}
		else {
			if ((PFCode = RARProcessFile(_rarFile, RAR_SKIP, NULL, NULL)) != 0) {
                [self assignError:error code:(NSInteger)PFCode];
                return nil;
			}
		}
	}
	
	if (length == 0) {
        [self assignError:error code:ERAR_ARCHIVE_NOT_FOUND];
		return nil;
	}
	
	UInt8 *buffer = (UInt8 *)malloc(length * sizeof(UInt8));
	UInt8 *callBackBuffer = buffer;
	
	RARSetCallback(_rarFile, CallbackProc, (long) &callBackBuffer);
	
	PFCode = RARProcessFile(_rarFile, RAR_TEST, NULL, NULL);

    if (PFCode != 0) {
        [self assignError:error code:(NSInteger)PFCode];
        return nil;
    }
    
    return [NSData dataWithBytesNoCopy:buffer length:length freeWhenDone:YES];
}

- (BOOL)closeFile;
{
	if (_rarFile)
		RARCloseArchive(_rarFile);
    _rarFile = 0;
    
    if (flags)
        delete flags->ArcName;
	delete flags, flags = 0;
    delete header, header = 0;
	return YES;
}



#pragma mark - Private Methods


- (BOOL)_unrarOpenFile:(NSString *)rarFile inMode:(NSInteger)mode withPassword:(NSString *)aPassword error:(NSError **)error
{
    if (error) {
        *error = nil;
    }
    
	header = new RARHeaderDataEx;
    bzero(header, sizeof(RARHeaderDataEx));
	flags = new RAROpenArchiveDataEx;
    bzero(flags, sizeof(RAROpenArchiveDataEx));
	
	const char *filenameData = (const char *) [rarFile UTF8String];
	flags->ArcName = new char[strlen(filenameData) + 1];
	strcpy(flags->ArcName, filenameData);
	flags->OpenMode = mode;
	
	_rarFile = RAROpenArchiveEx(flags);
	if (_rarFile == 0 || flags->OpenResult != 0) {
        [self assignError:error code:(NSInteger)flags->OpenResult];
		return NO;
    }
	
    if(aPassword != nil) {
        char *password = (char *) [aPassword UTF8String];
        RARSetPassword(_rarFile, password);
    }
    
	return YES;
}

- (NSString *)errorNameForErrorCode:(NSInteger)errorCode
{
    NSString *errorName;
    
    switch (errorCode) {
        case ERAR_END_ARCHIVE:
            errorName = @"ERAR_END_ARCHIVE";
            break;
            
        case ERAR_NO_MEMORY:
            errorName = @"ERAR_NO_MEMORY";
            break;
            
        case ERAR_BAD_DATA:
            errorName = @"ERAR_BAD_DATA";
            break;
            
        case ERAR_BAD_ARCHIVE:
            errorName = @"ERAR_BAD_ARCHIVE";
            break;
            
        case ERAR_UNKNOWN_FORMAT:
            errorName = @"ERAR_UNKNOWN_FORMAT";
            break;
            
        case ERAR_EOPEN:
            errorName = @"ERAR_EOPEN";
            break;
            
        case ERAR_ECREATE:
            errorName = @"ERAR_ECREATE";
            break;
            
        case ERAR_ECLOSE:
            errorName = @"ERAR_ECLOSE";
            break;
            
        case ERAR_EREAD:
            errorName = @"ERAR_EREAD";
            break;
            
        case ERAR_EWRITE:
            errorName = @"ERAR_EWRITE";
            break;
            
        case ERAR_SMALL_BUF:
            errorName = @"ERAR_SMALL_BUF";
            break;
            
        case ERAR_UNKNOWN:
            errorName = @"ERAR_UNKNOWN";
            break;
            
        case ERAR_MISSING_PASSWORD:
            errorName = @"ERAR_MISSING_PASSWORD";
            break;
            
        case ERAR_ARCHIVE_NOT_FOUND:
            errorName = @"ERAR_ARCHIVE_NOT_FOUND";
            break;
            
        default:
            errorName = [NSString stringWithFormat:@"Unknown error code: %u", flags->OpenResult];
            break;
    }
    
    return errorName;
}

- (BOOL)assignError:(NSError **)error code:(NSInteger)errorCode
{
    if (error) {
        NSString *errorName = [self errorNameForErrorCode:errorCode];
        
        *error = [NSError errorWithDomain:URRErrorDomain
                                     code:errorCode
                                 userInfo:@{NSUnderlyingErrorKey: errorName}];
    }
    
    return NO;
}

- (void)dealloc {
	[_filename release];
    [_password release];
	[super dealloc];
}

@end
