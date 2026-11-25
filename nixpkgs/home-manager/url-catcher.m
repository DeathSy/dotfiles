// Background app that catches http/https URLs and HTML file opens on headless
// Macs so CLI `open` calls don't launch Safari. Logs each URL to
// ~/Library/Logs/url-catcher.log, posts a notification, and exits when idle.
#import <Cocoa/Cocoa.h>
#import <fcntl.h>
#import <libproc.h>
#import <sys/stat.h>
#import <unistd.h>

static const NSTimeInterval kIdleTimeout = 3.0;

static NSString *sanitize(NSString *s) {
    NSCharacterSet *ctrl = [NSCharacterSet controlCharacterSet];
    return [[s componentsSeparatedByCharactersInSet:ctrl] componentsJoinedByString:@" "];
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
    // 0600 (and fchmod on existing files): URLs may carry OAuth code/state values.
    int fd = open(logPath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0600);
    if (fd >= 0) {
        (void)fchmod(fd, 0600);
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        (void)write(fd, data.bytes, data.length);
        close(fd);
    }
    // Show only the host in notifications (full URL stays in the 0600 log),
    // passed via argv so it is never interpolated into AppleScript.
    NSString *host = [NSURL URLWithString:cleanURL].host;
    NSString *what = host.length ? host : @"file";
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/osascript"];
    task.arguments = @[
        @"-e", @"on run argv",
        @"-e", @"display notification (item 1 of argv) with title \"URL caught\"",
        @"-e", @"end run",
        what
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

- (void)handleOpenDocs:(NSAppleEventDescriptor *)event
        withReplyEvent:(__unused NSAppleEventDescriptor *)reply {
    NSAppleEventDescriptor *direct = [event paramDescriptorForKeyword:keyDirectObject];
    if (!direct) return;
    if (direct.descriptorType == typeAEList) {
        for (NSInteger i = 1; i <= direct.numberOfItems; i++) {
            [self recordURL:[direct descriptorAtIndex:i].fileURLValue.absoluteString fromEvent:event];
        }
    } else {
        [self recordURL:direct.fileURLValue.absoluteString fromEvent:event];
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
