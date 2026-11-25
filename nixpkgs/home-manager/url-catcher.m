// Background app that catches http/https URLs and HTML file opens on headless
// Macs so CLI `open` calls don't launch Safari. Logs each URL to
// ~/Library/Logs/url-catcher.log, posts a notification, and exits when idle.
#import <Cocoa/Cocoa.h>
#import <fcntl.h>
#import <libproc.h>
#import <unistd.h>

static const NSTimeInterval kIdleTimeout = 3.0;

static NSString *sanitize(NSString *s) {
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"\r\n\t"];
    return [[s componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@" "];
}

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (nonatomic, strong) NSTimer *quitTimer;
@property (nonatomic, strong) NSISO8601DateFormatter *iso;
@end

@implementation AppDelegate

- (instancetype)init {
    if ((self = [super init])) {
        _iso = [[NSISO8601DateFormatter alloc] init];
        _iso.timeZone = [NSTimeZone localTimeZone];
        _iso.formatOptions = NSISO8601DateFormatWithInternetDateTime;
    }
    return self;
}

- (void)resetQuitTimer {
    [self.quitTimer invalidate];
    self.quitTimer = [NSTimer scheduledTimerWithTimeInterval:kIdleTimeout
                                                     repeats:NO
                                                       block:^(__unused NSTimer *t) {
        [NSApp terminate:nil];
    }];
}

- (void)recordURL:(NSString *)url fromEvent:(NSAppleEventDescriptor *)event {
    if (!url.length) return;

    NSString *pidStr = @"?";
    NSString *procName = @"?";
    NSAppleEventDescriptor *pidDesc = [event attributeDescriptorForKeyword:keySenderPIDAttr];
    if (pidDesc) {
        pid_t pid = (pid_t)[pidDesc int32Value];
        if (pid > 0) {
            pidStr = [NSString stringWithFormat:@"%d", pid];
            NSString *name = [NSRunningApplication runningApplicationWithProcessIdentifier:pid].localizedName;
            if (!name.length) {
                char buf[256] = {0};
                if (proc_name(pid, buf, (uint32_t)sizeof(buf)) > 0) {
                    name = [NSString stringWithUTF8String:buf];
                }
            }
            if (name.length) procName = sanitize(name);
        }
    }

    NSString *cleanURL = sanitize(url);
    NSString *line = [NSString stringWithFormat:@"%@\t%@\t%@\t%@\n",
                      [self.iso stringFromDate:[NSDate date]], pidStr, procName, cleanURL];

    NSString *logDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:logDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSString *logPath = [logDir stringByAppendingPathComponent:@"url-catcher.log"];
    int fd = open(logPath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd >= 0) {
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (write(fd, data.bytes, data.length) < 0) {}
        close(fd);
    }

    // Pass URL via argv so it is never interpolated into AppleScript.
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
    task.arguments = @[
        @"-e", @"on run argv",
        @"-e", @"display notification (item 1 of argv) with title \"URL caught\"",
        @"-e", @"end run",
        cleanURL
    ];
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    [task launchAndReturnError:nil];

    [self resetQuitTimer];
}

- (void)handleGetURL:(NSAppleEventDescriptor *)event
      withReplyEvent:(__unused NSAppleEventDescriptor *)reply {
    [self recordURL:[[event paramDescriptorForKeyword:keyDirectObject] stringValue] fromEvent:event];
}

- (void)recordDocDescriptor:(NSAppleEventDescriptor *)desc fromEvent:(NSAppleEventDescriptor *)event {
    NSURL *fileURL = desc.fileURLValue;
    if (fileURL) {
        [self recordURL:fileURL.absoluteString fromEvent:event];
    } else if (desc.stringValue.length) {
        NSString *s = desc.stringValue;
        NSString *url = [s hasPrefix:@"/"] ? [NSURL fileURLWithPath:s].absoluteString : s;
        [self recordURL:url fromEvent:event];
    }
}

- (void)handleOpenDocs:(NSAppleEventDescriptor *)event
        withReplyEvent:(__unused NSAppleEventDescriptor *)reply {
    NSAppleEventDescriptor *direct = [event paramDescriptorForKeyword:keyDirectObject];
    if (!direct) return;
    if (direct.descriptorType == typeAEList) {
        for (NSInteger i = 1; i <= direct.numberOfItems; i++) {
            [self recordDocDescriptor:[direct descriptorAtIndex:i] fromEvent:event];
        }
    } else {
        [self recordDocDescriptor:direct fromEvent:event];
    }
}

- (void)applicationWillFinishLaunching:(__unused NSNotification *)n {
    NSAppleEventManager *aem = [NSAppleEventManager sharedAppleEventManager];
    [aem setEventHandler:self
             andSelector:@selector(handleGetURL:withReplyEvent:)
           forEventClass:kInternetEventClass
              andEventID:kAEGetURL];
    [aem setEventHandler:self
             andSelector:@selector(handleOpenDocs:withReplyEvent:)
           forEventClass:kCoreEventClass
              andEventID:kAEOpenDocuments];
}

- (void)applicationDidFinishLaunching:(__unused NSNotification *)n {
    [self resetQuitTimer];
}

@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
