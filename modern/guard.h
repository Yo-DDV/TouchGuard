// SPDX-License-Identifier: MIT
#ifndef TOUCHGUARD_GUARD_H
#define TOUCHGUARD_GUARD_H
#include <stdbool.h>
#include <stdint.h>

typedef enum { TG_DOWN, TG_UP, TG_DRAG, TG_SCROLL } TGPointerEvent;
typedef struct {
    uint64_t deadline_ns;
    uint64_t blocked_buttons;
    uint64_t delay_ns;
    bool enabled;
} TGGuard;

void tg_init(TGGuard *guard);
bool tg_set_delay(TGGuard *guard, unsigned milliseconds);
void tg_reset(TGGuard *guard);
void tg_key(TGGuard *guard, uint64_t now_ns);
bool tg_pointer(TGGuard *guard, TGPointerEvent event, unsigned button,
                bool intentional_modifier, uint64_t now_ns);
#endif
