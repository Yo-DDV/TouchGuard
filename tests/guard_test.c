// SPDX-License-Identifier: MIT
#include "guard.h"
#include <assert.h>
#include <stdio.h>
#include <time.h>

int main(void) {
    TGGuard g;
    tg_init(&g);
    const uint64_t start = UINT64_C(1000000000);
    assert(!tg_pointer(&g, TG_DOWN, 0, false, start));
    tg_key(&g, start); // Both press and release use the same transition.
    assert(tg_pointer(&g, TG_DOWN, 0, false, start));
    assert(tg_pointer(&g, TG_DRAG, 0, true, start + 1));
    assert(tg_pointer(&g, TG_UP, 0, true, start + 300000001));
    assert(!g.blocked_buttons);
    assert(!tg_pointer(&g, TG_DOWN, 0, false, start + 300000000));
    tg_key(&g, start + 100000000);
    assert(tg_pointer(&g, TG_SCROLL, 0, false, start + 399999999));
    assert(!tg_pointer(&g, TG_SCROLL, 0, false, start + 400000000));
    // Modifier-click is intentional; Shift is not passed as a bypass modifier.
    tg_key(&g, start);
    assert(!tg_pointer(&g, TG_DOWN, 1, true, start));
    assert(!tg_pointer(&g, TG_UP, 1, false, start));
    assert(!tg_pointer(&g, TG_DOWN, 64, false, start));
    assert(tg_pointer(&g, TG_DOWN, 63, false, start));
    assert(tg_pointer(&g, TG_UP, 63, false, start));
    // Pausing cannot expose the release of a press that was already blocked.
    assert(tg_pointer(&g, TG_DOWN, 0, false, start));
    g.enabled = false;
    assert(tg_pointer(&g, TG_UP, 0, false, start));
    assert(!tg_pointer(&g, TG_DOWN, 0, false, start));
    tg_key(&g, start);
    assert(!tg_pointer(&g, TG_SCROLL, 0, false, start));
    g.enabled = true;
    tg_key(&g, start);
    assert(tg_pointer(&g, TG_DOWN, 0, false, start));
    assert(tg_set_delay(&g, 400));
    assert(tg_pointer(&g, TG_UP, 0, false, start));
    assert(!tg_set_delay(&g, 0));
    assert(!tg_set_delay(&g, 1001));
    assert(tg_set_delay(&g, 100));
    assert(!g.deadline_ns && !g.blocked_buttons);
    tg_key(&g, start);
    assert(tg_pointer(&g, TG_SCROLL, 0, false, start + 99999999));
    assert(!tg_pointer(&g, TG_SCROLL, 0, false, start + 100000000));
    tg_key(&g, UINT64_MAX - 1);
    assert(g.deadline_ns == UINT64_MAX);
    tg_reset(&g);
    assert(!tg_pointer(&g, TG_SCROLL, 0, false, start));
    puts("PASS: immediate activation, delay bounds, repeat extension, expiry,");
    puts("      click/drag pairing, modifiers, pause, recovery and overflow.");

    const unsigned iterations = 10000000;
    volatile unsigned suppressed = 0;
    struct timespec before, after;
    clock_gettime(CLOCK_MONOTONIC, &before);
    for (unsigned i = 0; i < iterations; ++i) {
        tg_key(&g, (uint64_t)i * 100);
        suppressed += tg_pointer(&g, TG_SCROLL, 0, false, (uint64_t)i * 100 + 1);
    }
    clock_gettime(CLOCK_MONOTONIC, &after);
    double elapsed = after.tv_sec - before.tv_sec + (after.tv_nsec - before.tv_nsec) / 1e9;
    assert(suppressed == iterations);
    printf("Core benchmark: %.2f ns per key+pointer pair (%u pairs).\n",
           elapsed * 1e9 / iterations, iterations);
    return 0;
}
