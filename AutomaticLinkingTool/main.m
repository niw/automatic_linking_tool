//
//  main.m
//  AutomaticLinkingTool
//
//  Created by Yoshimasa Niwa on 7/12/16.
//  Copyright © 2016 Yoshimasa Niwa. All rights reserved.
//

@import Foundation;
@import MachO;

static BOOL ReadBytesFromDataIfPossible(NSData *data, void *buffer, NSUInteger *position, NSUInteger length) {
    if (buffer && position) {
        if (data.length < *position + length) {
            return NO;
        } else {
            [data getBytes:buffer range:NSMakeRange(*position, length)];
            *position += length;
            return YES;
        }
    } else {
        return NO;
    }
}

static BOOL ListLinkerOptionCommands(NSString *inputPath) {
    NSError *error;

    NSData *data = [NSData dataWithContentsOfFile:inputPath options:NSDataReadingMappedIfSafe error:&error];
    if (!data) {
        NSLog(@"Fail to read filea at path: %@ error: %@", inputPath, error);
        return NO;
    }

    NSUInteger position = 0;

    NSUInteger headerStartPosition = position;
    struct mach_header_64 header;
    if (!ReadBytesFromDataIfPossible(data, &header.magic, &position, sizeof(header.magic))) {
        NSLog(@"Fail to read Mach-O magic.");
        return NO;
    }
    if (header.magic != MH_MAGIC_64) {
        NSLog(@"Unknown Mach-O magic: %zd", header.magic);
        return NO;
    }
    position = headerStartPosition;
    if (!ReadBytesFromDataIfPossible(data, &header, &position, sizeof(header))) {
        NSLog(@"Fail to read Mach-O header.");
        return NO;
    }

    BOOL isSwiftObject = NO;
    NSMutableArray<NSString *> *automaticLinkingOptionStrings = [[NSMutableArray alloc] initWithCapacity:header.ncmds];

    for (uint32_t index = 0; index < header.ncmds; index++) {
        NSUInteger commandStartPosition = position;
        struct load_command command;
        if (!ReadBytesFromDataIfPossible(data, &command, &position, sizeof(command))) {
            NSLog(@"Fail to read load command header.");
            return NO;
        }
        NSRange commandRange = NSMakeRange(commandStartPosition, command.cmdsize);

        switch (command.cmd) {
            case LC_LINKER_OPTION: {
                position = commandStartPosition;
                struct linker_option_command linkerOptionCommand;
                if (!ReadBytesFromDataIfPossible(data, &linkerOptionCommand, &position, sizeof(linkerOptionCommand))) {
                    NSLog(@"Fail to read linker option command header.");
                    return NO;
                }

                NSMutableArray<NSString *> *linkerOptionStrings = [[NSMutableArray alloc] initWithCapacity:linkerOptionCommand.count];
                for (uint32_t count = 0; count < linkerOptionCommand.count; count++) {
                    static uint8_t const nullByte = 0x00;
                    NSData *nullData = [NSData dataWithBytes:&nullByte length:sizeof(nullByte)];

                    NSRange nullTerminationRange = [data rangeOfData:nullData options:0 range:NSMakeRange(position, NSMaxRange(commandRange) - position)];
                    if (nullTerminationRange.location == NSNotFound && nullTerminationRange.length == 0) {
                        NSLog(@"No null termination found.");
                        return NO;
                    }

                    NSRange nullTerminatedStringRange = NSMakeRange(position, NSMaxRange(nullTerminationRange) - position);
                    NSData *nullTerminatedStringData = [data subdataWithRange:nullTerminatedStringRange];
                    NSString *string = [NSString stringWithUTF8String:nullTerminatedStringData.bytes];
                    [linkerOptionStrings addObject:string];

                    position = NSMaxRange(nullTerminationRange);
                }


                if (linkerOptionStrings.count == 1 && [linkerOptionStrings[0] hasPrefix:@"-l"]) {
                    [automaticLinkingOptionStrings addObject:linkerOptionStrings[0]];
                    if ([linkerOptionStrings[0] isEqualToString:@"-lswiftCore"]) {
                        isSwiftObject = YES;
                    }
                }
                if (linkerOptionStrings.count == 2 && [linkerOptionStrings[0] isEqualToString:@"-framework"]) {
                    [automaticLinkingOptionStrings addObject:[linkerOptionStrings componentsJoinedByString:@" "]];
                }

                break;
            }
            default:
                break;
        }

        position = NSMaxRange(commandRange);
    }

    NSMutableDictionary *resultDictionary = [[NSMutableDictionary alloc] init];
    resultDictionary[@"is_swift_object"] = @(isSwiftObject);
    resultDictionary[@"automatic_linking_options"] = automaticLinkingOptionStrings;

    NSData *resultJsonData = [NSJSONSerialization dataWithJSONObject:resultDictionary options:0 error:&error];
    if (error) {
        NSLog(@"Fail to generate JSON data: %@", error);
        return NO;
    }
    [[NSFileHandle fileHandleWithStandardOutput] writeData:resultJsonData];

    return YES;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *inputPath;
        if (argc > 1) {
            inputPath = [NSString stringWithUTF8String:argv[1]];
        } else {
            NSLog(@"Missing arguments.");
            return 1;
        }

        if (!ListLinkerOptionCommands(inputPath)) {
            NSLog(@"Fail to list linker option commands.");
            return 1;
        }

        return 0;
    }
}
