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

@interface TGApp : NSObject <NSApplicationDelegate, NSMenuDelegate> {
@public
    TGGuard guard;
    CFMachPortRef keyboardTap;
    CFMachPortRef pointerTap;
    uint64_t blocked;
@private
    NSStatusItem *_statusItem;
    NSMenuItem *_statusLine, *_toggleItem, *_loginItem, *_countLine;
    NSTimer *_permissionTimer;
    unsigned _permissionChecks;
    NSString *_failure;
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
        ++app->blocked;
        return NULL;
    }
    return event;
}

@implementation TGApp
- (instancetype)init {
    if ((self = [super init])) {
        tg_init(&guard);
        NSUserDefaults *prefs = NSUserDefaults.standardUserDefaults;
        [prefs registerDefaults:@{ @"enabled": @YES, @"delayMS": @300 }];
        guard.enabled = [prefs boolForKey:@"enabled"];
        NSInteger delay = [prefs integerForKey:@"delayMS"];
        if (delay >= 100 && delay <= 1000) tg_set_delay(&guard, (unsigned)delay);
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    _statusItem.button.image = [NSImage imageWithSystemSymbolName:@"hand.raised" accessibilityDescription:@"TouchGuard"];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"TouchGuard"];
    menu.delegate = self;
    _statusLine = [menu addItemWithTitle:@"TouchGuard" action:nil keyEquivalent:@""];
    _countLine = [menu addItemWithTitle:@"Blocked interactions: 0" action:nil keyEquivalent:@""];
    [menu addItem:NSMenuItem.separatorItem];
    _toggleItem = [menu addItemWithTitle:@"Protect While Typing" action:@selector(toggleGuard:) keyEquivalent:@""];
    _toggleItem.target = self;
    NSMenuItem *delayItem = [menu addItemWithTitle:@"Delay After Typing" action:nil keyEquivalent:@""];
    NSMenu *delays = [[NSMenu alloc] initWithTitle:@"Delay"];
    for (NSNumber *value in @[@100, @200, @300, @400, @500, @750, @1000]) {
        NSMenuItem *item = [delays addItemWithTitle:[NSString stringWithFormat:@"%@ ms", value]
                                            action:@selector(setDelay:) keyEquivalent:@""];
        item.tag = value.integerValue;
        item.target = self;
    }
    delayItem.submenu = delays;
    _loginItem = [menu addItemWithTitle:@"Start at Login" action:@selector(toggleLogin:) keyEquivalent:@""];
    _loginItem.target = self;
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *permission = [menu addItemWithTitle:@"Accessibility Settings…" action:@selector(openPermissions:) keyEquivalent:@""];
    permission.target = self;
    NSMenuItem *retry = [menu addItemWithTitle:@"Retry Protection" action:@selector(retry:) keyEquivalent:@""];
    retry.target = self;
    NSMenuItem *about = [menu addItemWithTitle:@"About TouchGuard" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    about.target = NSApp;
    [menu addItemWithTitle:@"Quit TouchGuard" action:@selector(terminate:) keyEquivalent:@"q"].target = NSApp;
    _statusItem.menu = menu;
    [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(woke:)
                                                          name:NSWorkspaceDidWakeNotification object:nil];
    [self retry:nil];
}

- (void)startTaps {
    if (keyboardTap && pointerTap) return;
    if (!AXIsProcessTrusted()) { _failure = @"Accessibility permission required"; return; }
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
        _failure = @"Input access unavailable — check macOS permissions";
        return;
    }
    for (unsigned i = 0; i < 2; ++i) {
        CFMachPortRef tap = i == 0 ? keyboardTap : pointerTap;
        CFRunLoopSourceRef source = CFMachPortCreateRunLoopSource(NULL, tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CFRelease(source);
        CGEventTapEnable(tap, true);
    }
    _failure = nil;
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

- (void)openPermissions:(id)sender {
    (void)sender;
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]];
}

- (void)toggleGuard:(id)sender {
    (void)sender;
    guard.enabled = !guard.enabled;
    guard.deadline_ns = 0;
    [NSUserDefaults.standardUserDefaults setBool:guard.enabled forKey:@"enabled"];
}

- (void)setDelay:(NSMenuItem *)sender {
    if (tg_set_delay(&guard, (unsigned)sender.tag)) {
        [NSUserDefaults.standardUserDefaults setInteger:sender.tag forKey:@"delayMS"];
    }
}

- (void)toggleLogin:(id)sender {
    (void)sender;
    NSError *error = nil;
    SMAppService *service = loginService();
    BOOL success = service.status == SMAppServiceStatusEnabled
        ? [service unregisterAndReturnError:&error] : [service registerAndReturnError:&error];
    if (!success) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Login-item registration failed";
        alert.informativeText = error.localizedDescription ?: @"Check Login Items in System Settings.";
        [alert runModal];
    } else if (service.status == SMAppServiceStatusRequiresApproval) {
        [SMAppService openSystemSettingsLoginItems];
    }
}

- (void)menuWillOpen:(NSMenu *)menu {
    BOOL ready = keyboardTap && pointerTap && CGEventTapIsEnabled(keyboardTap) && CGEventTapIsEnabled(pointerTap);
    _statusLine.title = _failure ?: (IsSecureEventInputEnabled() ? @"Protected input: temporarily unavailable"
                        : ready ? (guard.enabled ? @"Protection active" : @"Protection paused") : @"Protection unavailable");
    _countLine.title = [NSString stringWithFormat:@"Blocked interactions: %llu", (unsigned long long)blocked];
    _toggleItem.state = guard.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    _loginItem.state = loginService().status == SMAppServiceStatusEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    for (NSMenuItem *item in menu.itemArray) {
        for (NSMenuItem *delay in item.submenu.itemArray) {
            delay.state = (uint64_t)delay.tag * 1000000 == guard.delay_ns ? NSControlStateValueOn : NSControlStateValueOff;
        }
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [_permissionTimer invalidate];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self stopTaps];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL enableLogin = NO, disableLogin = NO;
        for (int i = 1; i < argc; ++i) {
            if (!strcmp(argv[i], "--integration-test")) return tg_native_probe();
            if (!strcmp(argv[i], "--enable-login")) enableLogin = YES;
            else if (!strcmp(argv[i], "--disable-login")) disableLogin = YES;
            else if (!strcmp(argv[i], "--status")) {
                NSDictionary *status = @{ @"accessibility": @(AXIsProcessTrusted()),
                    @"secureInput": @(IsSecureEventInputEnabled()),
                    @"loginStatus": @(loginService().status),
                    @"version": [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown" };
                NSData *json = [NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
                puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
                return 0;
            } else {
                fputs("Usage: TouchGuard [--enable-login | --disable-login | --status | --integration-test]\n", stderr);
                return 2;
            }
        }
        if (getuid() == 0) { fputs("Run TouchGuard as your regular user.\n", stderr); return 2; }
        if (enableLogin && disableLogin) return 2;
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
        NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
        if ([NSRunningApplication runningApplicationsWithBundleIdentifier:identifier].count > 1) return 0;
        [NSApplication sharedApplication];
        NSApp.activationPolicy = NSApplicationActivationPolicyAccessory;
        TGApp *delegate = [[TGApp alloc] init];
        NSApp.delegate = delegate;
        [NSApp run];
    }
    return 0;
}
