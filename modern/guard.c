// SPDX-License-Identifier: MIT
#include "guard.h"

void tg_init(TGGuard *guard) {
    *guard = (TGGuard){ .delay_ns = UINT64_C(300000000), .enabled = true };
}

bool tg_set_delay(TGGuard *guard, unsigned milliseconds) {
    if (milliseconds < 100 || milliseconds > 1000) return false;
    guard->delay_ns = (uint64_t)milliseconds * UINT64_C(1000000);
    guard->deadline_ns = 0;
    return true;
}

void tg_reset(TGGuard *guard) {
    guard->deadline_ns = 0;
    guard->blocked_buttons = 0;
}

void tg_key(TGGuard *guard, uint64_t now_ns) {
    if (!guard->enabled) return;
    guard->deadline_ns = now_ns > UINT64_MAX - guard->delay_ns
        ? UINT64_MAX : now_ns + guard->delay_ns;
}

bool tg_pointer(TGGuard *guard, TGPointerEvent event, unsigned button,
                bool intentional_modifier, uint64_t now_ns) {
    if (event != TG_SCROLL && button >= 64) return false;
    uint64_t bit = event == TG_SCROLL ? 0 : UINT64_C(1) << button;
    if (event == TG_UP && (guard->blocked_buttons & bit)) {
        guard->blocked_buttons &= ~bit;
        return true;
    }
    if (event == TG_DRAG && (guard->blocked_buttons & bit)) return true;
    bool active = guard->enabled && now_ns < guard->deadline_ns;
    if (event == TG_DOWN) guard->blocked_buttons &= ~bit;
    if (!active || intentional_modifier) return false;
    // A blocked press must retain its matching drag/release, even after expiry.
    if (event == TG_DOWN) guard->blocked_buttons |= bit;
    return event != TG_UP;
}
