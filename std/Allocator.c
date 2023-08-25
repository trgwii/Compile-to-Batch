#ifndef ALLOCATOR_H
#define ALLOCATOR_H

#include <stddef.h>
#include "Str.h"
#include "panic.c"

typedef void *Realloc(void *ptr, size_t size, size_t old_size, void *state);

typedef struct {
	Realloc *realloc;
	void *state;
} Allocator;

typedef struct {
	Str mem;
	size_t cur;
} Bump;

static Str alloc(Allocator ally, size_t size) {
	return (Str){
		.ptr = ally.realloc(NULL, size, 0, ally.state),
		.len = size,
	};
}

static Str resizeAllocation(Allocator ally, Str allocation, size_t new_size) {
	return (Str){
		.ptr = ally.realloc(allocation.ptr, new_size, allocation.len, ally.state),
		.len = new_size,
	};
}

static void *bumpRealloc(void *ptr, size_t size, size_t old_size, void *state) {
	Bump *bump = (Bump *)state;
	if (size == 0) {
		return NULL;
	}
	if (ptr != NULL) {
		if (bump->mem.ptr + bump->cur - old_size != ptr) {
			return NULL;
		}
	}

	if (bump->cur - old_size + size > bump->mem.len) {
		return NULL;
	}
	void *result = bump->mem.ptr + bump->cur - old_size;
	bump->cur += size - old_size;
	return result;
}

#endif /* ALLOCATOR_H */
