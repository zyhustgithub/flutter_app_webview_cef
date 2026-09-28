#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

namespace cef_ime {
struct Rect { double x = 0, y = 0, width = 1, height = 20; };
struct Geometry {
  // Affine Flutter logical-local -> HWND logical-client transform.
  double a = 1, b = 0, c = 0, d = 1, tx = 0, ty = 0, dpi = 1;
  int screen_x = 0, screen_y = 0;
  Rect monitor, work;
};
inline Rect Transform(const Rect& r, const Geometry& g) {
  double xs[4], ys[4];
  for (int i = 0; i < 4; ++i) {
    const double x = r.x + ((i & 1) ? r.width : 0);
    const double y = r.y + ((i & 2) ? r.height : 0);
    xs[i] = (g.a*x + g.c*y + g.tx)*g.dpi;
    ys[i] = (g.b*x + g.d*y + g.ty)*g.dpi;
  }
  const double x = std::floor(*std::min_element(xs, xs+4));
  const double y = std::floor(*std::min_element(ys, ys+4));
  return {x, y, std::max(1.0, std::ceil(*std::max_element(xs, xs+4))-x),
          std::max(1.0, std::ceil(*std::max_element(ys, ys+4))-y)};
}
inline Rect Caret(const std::vector<Rect>& bounds, int cursor) {
  if (bounds.empty()) return {};
  const int index = std::max(0, std::min(cursor, static_cast<int>(bounds.size())));
  Rect r = bounds[index == static_cast<int>(bounds.size()) ? index-1 : index];
  if (index == static_cast<int>(bounds.size())) r.x += r.width;
  r.width = 1;
  r.height = std::max(1.0, r.height);
  return r;
}
inline bool IsCurrent(int id, uint64_t epoch, int active, uint64_t generation) {
  return id >= 0 && id == active && epoch == generation;
}
struct Update {
  int browser = -1;
  uint64_t epoch = 0;
  bool editable = false;
  bool has_rect = false;
  Rect rect;
  int diagnostic = 0; // 1 focus applied, 2 context ready, 3 geometry IPC, 4 load end
  bool fallback = false;
};
enum class Input { Compose, Commit, Cancel };
struct CompositionState {
  bool composing = false;
  int cursor = 0;
  void Apply(Input kind, int length = 0, int position = 0) {
    composing = kind == Input::Compose && length > 0;
    cursor = composing ? std::max(0, std::min(position, length)) : 0;
  }
};
}  // namespace cef_ime
