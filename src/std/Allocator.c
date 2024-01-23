#ifndef ALLOCATOR_H
#define ALLOCATOR_H

#include "Result.h"
#include "defs.h"
#include "panic.c"
#include <stddef.h>

typedef void *Realloc(void *ptr, size_t size, size_t old_size, void *state);

typedef struct {
  Realloc *realloc;
  void *state;
} Allocator;

#ifdef BUILDING_WITH_ZIG
extern Result(Slice_void) alloc_(Allocator ally, size_t size, size_t length);
#else
static Result(Slice_void) alloc_(Allocator ally, size_t size, size_t length) {
  void *ptr = ally.realloc(NULL, size * length, 0, ally.state);
  if (!ptr) {
    return Result_Err(Slice_void, "alloc: out of memory");
  }
  Slice_void res = {.ptr = ptr, .len = length};
  return Result_Ok(Slice_void, res);
}
#endif

#define cast(expr, From, To)                                                   \
  (union {                                                                     \
    From from;                                                                 \
    To to;                                                                     \
  }){.from = expr}                                                             \
      .to

#define alloc(ally, T, length)                                                 \
  cast(alloc_(ally, sizeof(T), length), Result(Slice_void), Result(Slice_##T))

#ifdef BUILDING_WITH_ZIG
extern void resizeAllocation_(Allocator ally, Slice(void) * allocation,
                              size_t size, size_t new_length);
#else
static void resizeAllocation_(Allocator ally, Slice(void) * allocation,
                              size_t size, size_t new_length) {
  void *ptr = ally.realloc(allocation->ptr, size * new_length,
                           size * allocation->len, ally.state);
  if (!ptr) {
    return;
  }
  allocation->ptr = ptr;
  allocation->len = new_length;
}
#endif

#define resizeAllocation(ally, T, allocation, new_length)                      \
  resizeAllocation_(ally, cast(allocation, Slice(T) *, Slice(void) *),         \
                    sizeof(T), new_length)

typedef struct {
  Slice(char) mem;
  size_t cur;
} Bump;

#ifdef BUILDING_WITH_ZIG
extern void *bumpRealloc(void *ptr, size_t size, size_t old_size, void *state);
#else
static void *bumpRealloc(void *ptr, size_t size, size_t old_size, void *state) {
  Bump *bump = (Bump *)state;
  if (size == 0) {
    if (bump->mem.ptr + bump->cur - old_size == (char *)ptr) {
      // free in place
      bump->cur -= old_size;
    }
    // free of earlier allocation, waste memory
    return NULL;
  }
  if (ptr != NULL && bump->mem.ptr + bump->cur - old_size != (char *)ptr) {
    // moving resize
    // printf("(moving resize %zu -> %zu)\n", old_size, size);
    void *new_ptr = bumpRealloc(NULL, size, 0, state);
    if (!new_ptr)
      return NULL;
    for (size_t i = 0; i < size; i++) {
      ((char *)new_ptr)[i] = ((char *)ptr)[i];
    }
    return new_ptr;
  }

  size_t align = (8 - (((size_t)bump->mem.ptr + bump->cur) % 8)) % 8;

  if (bump->cur - old_size + size + align > bump->mem.len) {
    // OOM
    return NULL;
  }
  void *result = bump->mem.ptr + bump->cur - old_size + align;
  bump->cur += size - old_size + align;
  return result;
}
#endif

#endif /* ALLOCATOR_H */
