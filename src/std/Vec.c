#ifndef VEC_H
#define VEC_H

#include "Allocator.c"
#include "Result.h"
#include "Slice.h"
#include <stdbool.h>
#include <string.h>

#define Vec(T) Vec_##T

#define DefVec(T)                                                              \
  typedef struct {                                                             \
    Slice(T) slice;                                                            \
    Allocator ally;                                                            \
    size_t cap;                                                                \
  } Vec(T)

DefVec(void);
DefResult(Vec_void);
DefSlice(Slice_char);
DefVec(Slice_char);
DefResult(Vec_Slice_char);

#ifdef BUILDING_WITH_ZIG
extern bool append_(Vec(void) * v, size_t size, void *item);
extern bool appendMany_(Vec(void) * v, size_t size, void *items,
                        size_t items_len);
extern Result(Vec_void) createVec_(Allocator ally, size_t size, size_t cap);
extern void shrinkToLength_(Vec(void) * v, size_t size);
#else
static bool append_(Vec(void) * v, size_t size, void *item) {
  if (v->slice.len >= v->cap) {
    Slice(void) allocated = {
        .ptr = v->slice.ptr,
        .len = v->cap,
    };
    resizeAllocation_(v->ally, &allocated, size, v->cap * 2);
    v->slice.ptr = allocated.ptr;
    v->cap = allocated.len;
  }
  if (v->slice.len >= v->cap) {
    return false;
  }
  // printf("in loop %d\n", ((int *)item)[0]);
  for (size_t i = 0; i < size; i++) {

    ((char *)v->slice.ptr)[v->slice.len * size + i] = ((char *)item)[i];
  }
  v->slice.len++;
  return true;
}

static bool appendMany_(Vec(void) * v, size_t size, void *items,
                        size_t items_len) {
  for (size_t i = 0; i < items_len; i++) {
    if (!append_(v, size, (char *)items + (i * size))) {
      return false;
    }
  }
  return true;
}

static Result(Vec_void) createVec_(Allocator ally, size_t size, size_t cap) {
  Result(Slice_void) res = alloc_(ally, size, cap);
  if (!res.ok) {
    return Result_Err(Vec_void, res.err);
  }
  Vec(void) v = {
      .slice =
          {
              .ptr = res.val.ptr,
              .len = 0,
          },
      .ally = ally,
      .cap = cap,
  };
  return Result_Ok(Vec_void, v);
}

static void shrinkToLength_(Vec(void) * v, size_t size) {
  Slice(void) allocation = {
      .ptr = v->slice.ptr,
      .len = v->cap,
  };
  resizeAllocation_(v->ally, &allocation, size, v->slice.len);
  v->slice.ptr = allocation.ptr;
  v->cap = allocation.len;
}
#endif

#define append(v, T, item)                                                     \
  append_(cast(v, Vec(T) *, Vec(void) *), sizeof(T), cast(item, T *, void *))

#define appendMany(v, T, items, items_len)                                     \
  appendMany_(cast(v, Vec(T) *, Vec(void) *), sizeof(T),                       \
              cast(items, T *, void *), items_len)

#define appendSlice(v, T, items) appendMany(v, T, items.ptr, items.len)

#define appendManyCString(v, items) appendMany(v, char, items, strlen(items))

#define createVec(ally, T, cap)                                                \
  cast(createVec_(ally, sizeof(T), cap), Result(Vec_void), Result(Vec_##T))

#define shrinkToLength(v, T)                                                   \
  shrinkToLength_(cast(v, Vec(T) *, Vec(void) *), sizeof(T))

#endif /* VEC_H */
