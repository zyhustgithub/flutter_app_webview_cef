#include "ime_geometry.h"
#include <cassert>
#include <cmath>
#include <iostream>

int main() {
  using namespace cef_ime;
  Geometry g;
  g.tx = 100; g.ty = 48;
  for (double dpi : {1.0, 1.25, 1.5, 2.0}) {
    g.dpi = dpi;
    const auto r = Transform({20, 40, 1, 20}, g);
    assert(r.x == std::floor(120*dpi));
    assert(r.y == std::floor(88*dpi));
    assert(r.height >= 20*dpi);
  }
  g.a = 0; g.b = 1; g.c = -1; g.d = 0; g.dpi = 1;
  const auto rotated = Transform({10,20,2,15},g);
  assert(rotated.x == 65 && rotated.y == 58 && rotated.width == 15 && rotated.height == 2);
  std::vector<Rect> chars{{10,20,9,18},{19,20,11,18},{10,38,9,18}};
  assert(Caret(chars,0).x == 10);
  assert(Caret(chars,1).x == 19);
  assert(Caret(chars,2).y == 38);
  assert(Caret(chars,3).x == 19);
  assert(Caret(chars,999).x == 19);
  assert(Caret(chars,-1).x == 10);
  assert(Caret({},0).height > 0);
  assert(IsCurrent(2,8,2,8));
  assert(!IsCurrent(2,7,2,8));
  assert(!IsCurrent(1,8,2,8));
  assert(!IsCurrent(-1,8,-1,8));
  CompositionState state;
  state.Apply(Input::Compose, 5, 2);
  assert(state.composing && state.cursor == 2);
  state.Apply(Input::Compose, 3, 5);
  assert(state.composing && state.cursor == 3);
  state.Apply(Input::Commit);
  assert(!state.composing && state.cursor == 0);
  state.Apply(Input::Compose, 2, 1); // result + a new preedit in one OS message
  assert(state.composing);
  state.Apply(Input::Cancel);
  assert(!state.composing);
  state.Apply(Input::Compose, 0, 0); // deleting the entire preedit cancels it
  assert(!state.composing);
  std::cout << "IME geometry and generation checks passed\n";
}
