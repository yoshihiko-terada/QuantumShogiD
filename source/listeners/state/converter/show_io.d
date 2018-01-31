module listeners.state.converter.showr_io;

import std.algorithm;
import std.array;
import vibe.vibe;

import core.gs;
import listeners.state.converter.show_board;
import listeners.state.converter.show_inhand;
import listeners.state.converter.show_remains;


Json fromShowResp(ShowResp sr) {
  return Json([
    "sideOn": Json(sr.sideOn),
    "board": fromBoard(sr.board),
    "tInHand": fromInHand(sr.tInHand),
    "fInHand": fromInHand(sr.fInHand),
    "timer": fromRemains(sr.remains)
  ]);
}

Json fromPieceResp(PieceResp p) {
  auto filteredPoss = p.possibility[].filter!((pt) {
    return pt.length > 0;
  }).array;
  if (filteredPoss.length == 0) {
    return Json(null);
  } else {
    return Json([
      "face": Json(p.face),
      "possibility": Json(filteredPoss.map!((str) {
        return Json(str);
      }).array)
    ]);
  }
}