// SPDX-License-Identifier: MIT
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <ServiceManagement/ServiceManagement.h>
#include <time.h>
#include "guard.h"

int tg_native_probe(void);

static SMAppService *loginService(void) {
    return [SMAppService agentServiceWithPlistName:@"dev.yoddv.TouchGuard.plist"];
}

static NSString *const preferencesID = @"dev.yoddv.TouchGuard";
static NSString *const settingsNotification = @"dev.yoddv.TouchGuard.settings";
static NSString *const stopNotification = @"dev.yoddv.TouchGuard.stop";

static NSUserDefaults *preferences(void) {
    NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
    [prefs registerDefaults:@{ @"enabled": @YES, @"delayMS": @300 }];
    return prefs;
}

static unsigned delayMS(NSUserDefaults *prefs) {
    id value = [prefs objectForKey:@"delayMS"];
    return [value isKindOfClass:NSNumber.class] && [value integerValue] >= 100
        && [value integerValue] <= 1000 ? (unsigned)[value integerValue] : 300;
}

@interface TGApp : NSObject <NSApplicationDelegate> {
@public
    TGGuard guard;
    CFMachPortRef keyboardTap;
    CFMachPortRef pointerTap;
@private
    NSTimer *_permissionTimer;
    unsigned _permissionChecks;
}
- (instancetype)init;
- (void)startTaps;
- (void)stopTaps;
- (void)recoverTaps;
@end

static uint64_t now_ns(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }

static CGEventRef keyboardCallback(CGEventTapProxy proxy, CGEventType type,
                                   CGEventRef event, void *context) {
    (void)proxy;
    TGApp *app = (__bridge TGApp *)context;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        [app recoverTaps];
    } else if (type == kCGEventKeyDown || type == kCGEventKeyUp) {
        tg_key(&app->guard, now_ns());
    }
    // Listen-only: never read characters or alter keyboard events.
    return event;
}

static CGEventRef pointerCallback(CGEventTapProxy proxy, CGEventType type,
                                  CGEventRef event, void *context) {
    (void)proxy;
    TGApp *app = (__bridge TGApp *)context;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        [app recoverTaps];
        return event;
    }
    if (IsSecureEventInputEnabled()) {
        tg_reset(&app->guard);
        return event;
    }
    TGPointerEvent kind;
    unsigned button = 0;
    switch (type) {
        case kCGEventLeftMouseDown: kind = TG_DOWN; break;
        case kCGEventLeftMouseUp: kind = TG_UP; break;
        case kCGEventLeftMouseDragged: kind = TG_DRAG; break;
        case kCGEventRightMouseDown: kind = TG_DOWN; button = 1; break;
        case kCGEventRightMouseUp: kind = TG_UP; button = 1; break;
        case kCGEventRightMouseDragged: kind = TG_DRAG; button = 1; break;
        case kCGEventOtherMouseDown: kind = TG_DOWN; goto otherButton;
        case kCGEventOtherMouseUp: kind = TG_UP; goto otherButton;
        case kCGEventOtherMouseDragged: kind = TG_DRAG; goto otherButton;
        case kCGEventScrollWheel: kind = TG_SCROLL; break;
        default: return event;
    }
    goto decide;
otherButton:
    button = (unsigned)CGEventGetIntegerValueField(event, kCGMouseEventButtonNumber);
decide:;
    CGEventFlags flags = CGEventGetFlags(event);
    BOOL intentional = (flags & (kCGEventFlagMaskCommand | kCGEventFlagMaskControl |
                                 kCGEventFlagMaskAlternate)) != 0;
    if (tg_pointer(&app->guard, kind, button, intentional, now_ns())) {
        return NULL;
    }
    return event;
}

@implementation TGApp
- (instancetype)init {
    if ((self = [super init])) {
        tg_init(&guard);
        [self loadPreferences];
    }
    return self;
}

- (void)loadPreferences {
    NSUserDefaults *prefs = preferences();
    [prefs synchronize];
    BOOL enabled = [prefs boolForKey:@"enabled"];
    if (guard.enabled != enabled) guard.deadline_ns = 0;
    guard.enabled = enabled;
    unsigned delay = delayMS(prefs);
    if (guard.delay_ns != (uint64_t)delay * 1000000) tg_set_delay(&guard, delay);
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    NSDistributedNotificationCenter *center = NSDistributedNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(settingsChanged:) name:settingsNotification object:preferencesID];
    [center addObserver:self selector:@selector(stopRequested:) name:stopNotification object:preferencesID];
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(woke:)
                                                          name:NSWorkspaceDidWakeNotification object:nil];
    [self retry:nil];
}

- (void)settingsChanged:(NSNotification *)notification {
    (void)notification;
    [self loadPreferences];
    [self startTaps];
}

- (void)stopRequested:(NSNotification *)notification {
    (void)notification;
    [NSApp terminate:nil];
}

- (void)startTaps {
    if (keyboardTap && pointerTap) return;
    if (!AXIsProcessTrusted()) return;
    CGEventMask keys = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp);
    CGEventMask pointer = CGEventMaskBit(kCGEventLeftMouseDown) | CGEventMaskBit(kCGEventLeftMouseUp)
        | CGEventMaskBit(kCGEventLeftMouseDragged) | CGEventMaskBit(kCGEventRightMouseDown)
        | CGEventMaskBit(kCGEventRightMouseUp) | CGEventMaskBit(kCGEventRightMouseDragged)
        | CGEventMaskBit(kCGEventOtherMouseDown) | CGEventMaskBit(kCGEventOtherMouseUp)
        | CGEventMaskBit(kCGEventOtherMouseDragged) | CGEventMaskBit(kCGEventScrollWheel);
    keyboardTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                                   kCGEventTapOptionListenOnly, keys, keyboardCallback, (__bridge void *)self);
    pointerTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap,
                                  kCGEventTapOptionDefault, pointer, pointerCallback, (__bridge void *)self);
    if (!keyboardTap || !pointerTap) {
        [self stopTaps];
        fputs("Input access unavailable; check Accessibility permission.\n", stderr);
        return;
    }
    for (unsigned i = 0; i < 2; ++i) {
        CFMachPortRef tap = i == 0 ? keyboardTap : pointerTap;
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CFRelease(source);
        CGEventTapEnable(tap, true);
    }
    [_permissionTimer invalidate];
    _permissionTimer = nil;
}

- (void)stopTaps {
    tg_reset(&guard);
    if (keyboardTap) { CFMachPortInvalidate(keyboardTap); CFRelease(keyboardTap); keyboardTap = NULL; }
    if (pointerTap) { CFMachPortInvalidate(pointerTap); CFRelease(pointerTap); pointerTap = NULL; }
}

- (void)recoverTaps {
    tg_reset(&guard); // Fail open during recovery, rather than retaining a blocked press.
    if (AXIsProcessTrusted()) {
        if (keyboardTap) CGEventTapEnable(keyboardTap, true);
        if (pointerTap) CGEventTapEnable(pointerTap, true);
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{ [self stopTaps]; });
    }
}

- (void)retry:(id)sender {
    (void)sender;
    [self startTaps];
    if (keyboardTap && pointerTap) return;
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES});
    [_permissionTimer invalidate];
    _permissionChecks = 0;
    // Only while waiting for initial consent; active protection has no timer.
    _permissionTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self
                                                    selector:@selector(checkPermission:)
                                                    userInfo:nil repeats:YES];
}

- (void)checkPermission:(NSTimer *)timer {
    [self startTaps];
    if (++_permissionChecks >= 120) { [timer invalidate]; _permissionTimer = nil; }
}

- (void)woke:(NSNotification *)notification {
    (void)notification;
    [self stopTaps];
    [self startTaps];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [_permissionTimer invalidate];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [NSDistributedNotificationCenter.defaultCenter removeObserver:self];
    [self stopTaps];
}
@end

static int usage(void) {
    fputs("Usage: TouchGuard [--status | --pause | --resume | --delay-ms 100..1000 | "
          "--stop | --enable-login | --disable-login | --integration-test]\n", stderr);
    return 2;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (getuid() == 0) { fputs("Run TouchGuard as your regular user.\n", stderr); return 2; }
        if (argc > 1) {
            NSUserDefaults *prefs = preferences();
            if (argc == 2 && !strcmp(argv[1], "--integration-test")) return tg_native_probe();
            if (argc == 2 && !strcmp(argv[1], "--status")) {
                BOOL running = NO;
                for (NSRunningApplication *app in [NSRunningApplication runningApplicationsWithBundleIdentifier:preferencesID])
                    if (app.processIdentifier != getpid()) running = YES;
                NSDictionary *status = @{ @"accessibility": @(AXIsProcessTrusted()),
                    @"secureInput": @(IsSecureEventInputEnabled()), @"running": @(running),
                    @"enabled": @([prefs boolForKey:@"enabled"]), @"delayMS": @(delayMS(prefs)),
                    @"loginStatus": @(loginService().status),
                    @"version": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown" };
                NSData *json = [NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
                puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
                return 0;
            }
            BOOL enableLogin = argc == 2 && !strcmp(argv[1], "--enable-login");
            BOOL disableLogin = argc == 2 && !strcmp(argv[1], "--disable-login");
            if (enableLogin || disableLogin) {
                SMAppService *service = loginService();
                NSError *error = nil;
                BOOL success = YES;
                if (enableLogin && service.status != SMAppServiceStatusEnabled && service.status != SMAppServiceStatusRequiresApproval)
                    success = [service registerAndReturnError:&error];
                if (disableLogin && service.status != SMAppServiceStatusNotRegistered)
                    success = [service unregisterAndReturnError:&error];
                if (!success) { fputs(error.localizedDescription.UTF8String, stderr); fputc('\n', stderr); return 1; }
                if (service.status == SMAppServiceStatusRequiresApproval) {
                    [SMAppService openSystemSettingsLoginItems];
                    return 3;
                }
                printf("Login service status: %ld\n", (long)service.status);
                return 0;
            }
            if (argc == 2 && !strcmp(argv[1], "--stop")) {
                [NSDistributedNotificationCenter.defaultCenter postNotificationName:stopNotification
                                          object:preferencesID userInfo:nil deliverImmediately:YES];
                return 0;
            }
            if (argc == 2 && (!strcmp(argv[1], "--pause") || !strcmp(argv[1], "--resume"))) {
                [prefs setBool:!strcmp(argv[1], "--resume") forKey:@"enabled"];
            } else if (argc == 3 && !strcmp(argv[1], "--delay-ms")) {
                const char *value = argv[2];
                if (!*value || strlen(value) > 4) return usage();
                for (const char *p = value; *p; ++p) if (*p < '0' || *p > '9') return usage();
                unsigned delay = (unsigned)strtoul(value, NULL, 10);
                if (delay < 100 || delay > 1000) return usage();
                [prefs setInteger:delay forKey:@"delayMS"];
            } else return usage();
            if (![prefs synchronize]) { fputs("Could not save settings.\n", stderr); return 1; }
            // Notifications carry no settings or input data; the peer reloads its own preferences.
            [NSDistributedNotificationCenter.defaultCenter postNotificationName:settingsNotification
                                      object:preferencesID userInfo:nil deliverImmediately:YES];
            return 0;
        }
        if ([NSRunningApplication runningApplicationsWithBundleIdentifier:preferencesID].count > 1) return 0;
        [NSApplication sharedApplication];
        NSApp.activationPolicy = NSApplicationActivationPolicyAccessory;
        TGApp *delegate = [[TGApp alloc] init];
        NSApp.delegate = delegate;
        [NSApp run];
    }
    return 0;
}
