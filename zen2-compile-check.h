#ifndef CHARCOAL_ZEN2_COMPILE_CHECK_H
#define CHARCOAL_ZEN2_COMPILE_CHECK_H

/* Force-included through KCFLAGS for every kernel C translation unit. */
#if !defined(__znver2) || !defined(__znver2__) || !defined(__tune_znver2__)
#error "Charcoal kernel C compilation must target AMD Zen 2 (znver2)"
#endif

#endif /* CHARCOAL_ZEN2_COMPILE_CHECK_H */
