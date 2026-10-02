// SPDX-License-Identifier: MIT
// Explicit opt-in probe: its own temporary window; no access to other app text.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

@interface TGProbeView : NSView
@property unsigned clicks, keys, drags, scrolls;
@end
@implementation TGProbeView
- (BOOL)acceptsFirstResponder { return YES; }
- (void)drawRect:(NSRect)rect {
    (void)rect;
    [@"Temporary TouchGuard verification\n\nOnly synthetic test input is needed.\nThis window closes automatically."
       drawAtPoint:NSMakePoint(25, 100) withAttributes:@{NSFontAttributeName: [NSFont systemFontOfSize:16]}];
}
- (void)mouseDown:(NSEvent *)event { (void)event; ++_clicks; }
- (void)mouseDragged:(NSEvent *)event { (void)event; ++_drags; }
- (void)keyDown:(NSEvent *)event { (void)event; ++_keys; }
- (void)scrollWheel:(NSEvent *)event { (void)event; ++_scrolls; }
@end

@interface TGProbe : NSObject <NSApplicationDelegate>
@property NSWindow *window;
@property TGProbeView *view;
@property NSRunningApplication *previous;
@property CGPoint location;
@property BOOL controlPassed, protectionPassed;
@property int result;
- (BOOL)hasFocus;
@end

static void postClick(CGPoint p) {
    CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, p, kCGMouseButtonLeft);
    CGEventRef up = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp, p, kCGMouseButtonLeft);
    CGEventSetFlags(down, 0); CGEventSetFlags(up, 0);
    CGEventPost(kCGHIDEventTap, down); CGEventPost(kCGHIDEventTap, up);
    CFRelease(down); CFRelease(up);
}

@implementation TGProbe
- (BOOL)hasFocus {
    BOOL ours = NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier == getpid()
        && self.window.isKeyWindow;
    if (!ours) {
        fputs("Native probe cancelled: its window no longer owns focus.\n", stderr);
        self.result = 2;
        [self.window orderOut:nil];
        [NSApp stop:nil];
        [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint
            modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:NO];
    }
    return ours;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(250, 250, 480, 260)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"TouchGuard — temporary verification";
    self.view = [[TGProbeView alloc] initWithFrame:NSMakeRect(0, 0, 480, 260)];
    self.window.contentView = self.view;
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.view];
    [NSApp activate];
    NSPoint p = [self.window convertPointToScreen:NSMakePoint(240, 100)];
    self.location = CGPointMake(p.x, NSMaxY(NSScreen.screens.firstObject.frame) - p.y);
    [self performSelector:@selector(controlClick) withObject:nil afterDelay:1.2];
}
- (void)controlClick {
    if (![self hasFocus]) return;
    postClick(self.location);
    [self performSelector:@selector(arm) withObject:nil afterDelay:0.15];
}
- (void)arm {
    if (![self hasFocus]) return;
    self.controlPassed = self.view.clicks == 1;
    CGEventRef down = CGEventCreateKeyboardEvent(NULL, 0, true);
    CGEventRef up = CGEventCreateKeyboardEvent(NULL, 0, false);
    CGEventSetFlags(down, 0); CGEventSetFlags(up, 0);
    CGEventPost(kCGHIDEventTap, down); CGEventPost(kCGHIDEventTap, up);
    CFRelease(down); CFRelease(up);
    [self performSelector:@selector(attemptBlockedClick) withObject:nil afterDelay:0.04];
}
- (void)attemptBlockedClick {
    if (![self hasFocus]) return;
    postClick(self.location);
    [self performSelector:@selector(checkProtection) withObject:nil afterDelay:0.03];
}
- (void)checkProtection {
    self.protectionPassed = self.view.keys == 1 && self.view.clicks == 1;
    NSInteger milliseconds = [NSUserDefaults.standardUserDefaults integerForKey:@"delayMS"];
    if (milliseconds < 100 || milliseconds > 1000) milliseconds = 300;
    [self performSelector:@selector(afterDelayClick) withObject:nil afterDelay:milliseconds / 1000.0 + 0.15];
}
- (void)afterDelayClick {
    if (![self hasFocus]) return;
    postClick(self.location);
    [self performSelector:@selector(finish) withObject:nil afterDelay:0.15];
}
- (void)finish {
    BOOL restored = self.view.clicks == 2;
    self.result = self.controlPassed && self.protectionPassed && restored ? 0 : 1;
    printf("{\"controlClick\":%s,\"blockedAfterKey\":%s,\"restoredAfterDelay\":%s,\"deliveredKeys\":%u,\"deliveredClicks\":%u}\n",
           self.controlPassed ? "true" : "false", self.protectionPassed ? "true" : "false",
           restored ? "true" : "false", self.view.keys, self.view.clicks);
    [self.window orderOut:nil];
    [self.previous activateWithOptions:0];
    [NSApp stop:nil];
    [NSApp postEvent:[NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint
        modifierFlags:0 timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0] atStart:NO];
}
@end

int tg_native_probe(void) {
    if (!AXIsProcessTrusted()) { fputs("Accessibility permission is required for the native probe.\n", stderr); return 2; }
    [NSApplication sharedApplication];
    NSApp.activationPolicy = NSApplicationActivationPolicyRegular;
    TGProbe *probe = [[TGProbe alloc] init];
    probe.result = 1;
    probe.previous = NSWorkspace.sharedWorkspace.frontmostApplication;
    NSApp.delegate = probe;
    [NSApp run];
    return probe.result;
}
