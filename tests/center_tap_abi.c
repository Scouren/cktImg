/* Additive filled-circle C ABI contract.
 * Literal kind 4 makes the current ABI reject registration at runtime,
 * rather than failing to compile against an as-yet absent enum name.
 * The implementation must also publish CKTIMG_OP_FILLED_CIRCLE = 4. */
#include "cktimg.h"

#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* Run a second compilation with -DCKTIMG_TEST_PUBLISHED_FILLED_CIRCLE=1.
 * It must fail until the public header publishes the new constant. The
 * ordinary compilation still tests literal kind 4 at runtime independently. */
#ifdef CKTIMG_TEST_PUBLISHED_FILLED_CIRCLE
typedef char published_filled_circle_is_four[
    CKTIMG_OP_FILLED_CIRCLE == 4 ? 1 : -1];
#endif

static int failures = 0;
#define CHECK(c)                                                               \
  do {                                                                         \
    if (!(c)) {                                                                \
      fprintf(stderr, "center_tap_abi.c:%d: %s\n", __LINE__, #c);               \
      failures++;                                                              \
    }                                                                          \
  } while (0)

/* Independent mirror-then-clockwise-rotation oracle from the public header.
 * No drawing accessor supplies the expected transformed center. */
static void placed(const CktimgSch *s, size_t d, int32_t x, int32_t y,
                   int32_t *px, int32_t *py) {
  int32_t ox = 0, oy = 0, tx = 0, ty = 0;
  CHECK(cktimg_device_pos(s, d, &ox, &oy));
  if (cktimg_device_mirror(s, d)) x = -x;
  switch (cktimg_device_rot(s, d)) {
  case 0: tx = x; ty = y; break;
  case 1: tx = -y; ty = x; break;
  case 2: tx = -x; ty = -y; break;
  case 3: tx = y; ty = -x; break;
  default: CHECK(0); break;
  }
  *px = ox + tx;
  *py = oy + ty;
}

int main(void) {
  CHECK(CKTIMG_OP_LINE == 0 && CKTIMG_OP_POLYLINE == 1);
  CHECK(CKTIMG_OP_CIRCLE == 2 && CKTIMG_OP_TEXT == 3);
  CHECK(CKTIMG_OP_NONE == 255);

  /* The public bad-argument contract rejects circle bounds which cannot
   * be represented, before publishing a class. Check both circle kinds. */
  for (uint8_t kind = 2; kind <= 4; kind += 2) {
    const int32_t invalid[][3] = {
        {0, 0, -1}, {INT32_MAX, 0, 1}, {INT32_MIN, 0, 1},
        {0, INT32_MAX, 1}, {0, INT32_MIN, 1}};
    for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); ++i) {
      CktimgLib *probe = cktimg_lib_new();
      CHECK(probe != NULL);
      if (!probe) return 1;
      CktimgTerminal terminal = {"p", 0, 0, 0};
      CktimgOp circle = {kind, invalid[i], 1, invalid[i][2], NULL, 0};
      CHECK(cktimg_lib_add(probe, "invalid_disk", CKTIMG_ROLE_NONE,
                           &terminal, 1, &circle, 1) == SIZE_MAX);
      CHECK(cktimg_lib_count(probe) == 0);
      cktimg_lib_free(probe);
    }
  }
  CktimgLib *lib = cktimg_lib_new();
  CHECK(lib != NULL);
  if (!lib) return 1;

  /* All five operations use the same existing public CktimgOp record. The
   * offset filled disk extends beyond every other stroke and terminal. */
  CktimgTerminal terms[] = {{"a", -40, 0, 0}, {"b", 40, 0, 0}};
  int32_t line[] = {-40, 0, 40, 0};
  int32_t path[] = {-6, -4, 0, 4, 6, -4};
  int32_t hollow[] = {-7, 11}, text[] = {0, -10}, filled[] = {70, 17};
  CktimgOp ops[] = {
      {0, line, 2, 0, NULL, 0}, {1, path, 3, 0, NULL, 0},
      {2, hollow, 1, 3, NULL, 0}, {3, text, 1, 0, "ink", 11},
      {4, filled, 1, 9, NULL, 0}};
  size_t id = cktimg_lib_add(lib, "disk_probe", CKTIMG_ROLE_NONE,
                            terms, 2, ops, 5);
  CHECK(id != SIZE_MAX); /* Meaningful baseline RED: kind 4 is rejected. */
  if (id == SIZE_MAX) {
    cktimg_lib_free(lib);
    return 1;
  }
  /* Registration copies caller storage, including new circle geometry. */
  filled[0] = 900;
  ops[4].r = 99;

  CktimgSch *s = cktimg_parse_place(lib,
      "filled disk\n.subckt disk_probe a b\n.ends\nX1 p q disk_probe\n",
      NULL, NULL);
  CHECK(s != NULL);
  if (!s) {
    cktimg_lib_free(lib);
    return 1;
  }
  size_t d = SIZE_MAX;
  for (size_t i = 0; i < cktimg_device_count(s); ++i)
    if (strcmp(cktimg_device_name(s, i), "x1") == 0) d = i;
  CHECK(d != SIZE_MAX);
  if (d != SIZE_MAX) {
    CHECK(cktimg_device_op_count(s, d) == 5);
    for (size_t k = 0; k < 5; ++k)
      CHECK(cktimg_device_op_kind(s, d, k) == (uint8_t)k);
    CHECK(cktimg_device_op_kind(s, d, 5) == CKTIMG_OP_NONE);
    int32_t x, y, radius, ex, ey;
    CHECK(cktimg_device_op_circle(s, d, 2, &x, &y, &radius));
    placed(s, d, -7, 11, &ex, &ey);
    CHECK(x == ex && y == ey && radius == 3);
    CHECK(cktimg_device_op_circle(s, d, 4, &x, &y, &radius));
    placed(s, d, 70, 17, &ex, &ey);
    CHECK(x == ex && y == ey && radius == 9);
    CHECK(cktimg_device_op_circle(s, d, 4, NULL, NULL, NULL));
    CHECK(!cktimg_device_op_circle(s, d, 0, &x, &y, &radius));
    CHECK(!cktimg_device_op_circle(NULL, d, 4, &x, &y, &radius));
    CHECK(!cktimg_device_op_circle(s, d, 5, &x, &y, &radius));
    CHECK(cktimg_device_op_points(s, d, 4, NULL, 0) == 0);

    int32_t minx, miny, maxx, maxy;
    CHECK(cktimg_device_bounds(s, d, &minx, &miny, &maxx, &maxy));
    CHECK(minx <= ex - 9 && miny <= ey - 9);
    CHECK(maxx >= ex + 9 && maxy >= ey + 9);
    int32_t sx0, sy0, sx1, sy1;
    CHECK(cktimg_bounds(s, &sx0, &sy0, &sx1, &sy1));
    CHECK(sx0 <= minx && sy0 <= miny && sx1 >= maxx && sy1 >= maxy);
  }
  cktimg_sch_free(s);
  cktimg_lib_free(lib);
  return failures ? 1 : 0;
}
