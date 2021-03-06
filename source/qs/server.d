module qs.server;

import core.time;
import std.array;
import std.algorithm;
import std.math;

public import qs.pos;
public import qs.rule.piece_type;
import qs.rule.quantum.decide;
import qs.rule.quantum.origin;
public import qs.rule.quantum.quantum;
public import qs.timer;

alias void delegate(Pos pos, Quantum q) FieldShow;
alias void delegate(bool sideInTern) TurnChangeCallback;
alias void delegate(bool sideWin) GOverCallback;

interface ServerInterface {
	void start();
	void setCallbacks(TurnChangeCallback tcc, GOverCallback goc);
	bool getInTern();
	void show(FieldShow callback);
	void showInHand(bool side, void delegate(Quantum q) callback);
	Quantum get(Pos at);
	Quantum getInHand(bool side, int at);
	void aHandPut(bool side, Quantum q, Pos to);
	bool aHandStep(bool side, Pos from, Pos to, bool delegate() listenReface);
	Remains getRemains();
}
class Server : ServerInterface {
	Timer gameTimer;

	Quantum[] inHandT;
	Quantum[] inHandF;
	Origin originT;
	Origin originF;

	bool inTern;
	Quantum[9][9] field;

	TurnChangeCallback[] turnChangeCallback;
	GOverCallback[] gOverCallback;

	this(Timer gameTimer) {
		this.gameTimer = gameTimer;
		this.gameTimer.addCallback((bool side, bool result) {
			if (result) {
				foreach(goc; this.gOverCallback) {
					goc(side);
				}
			}
		});
		this.inTern = true;

		foreach (y; 0..9) {
			foreach (x; 0..9) {
				this.field[y][x] = null;
			}
		}

		this.originT = new Origin(true, (x, y, q) {
			this.field[y][x] = q;
		});
		this.originF = new Origin(false, (x, y, q) {
			this.field[y][x] = q;
		});

		this.inHandT = [];
		this.inHandF = [];

		this.turnChangeCallback = [];
		this.gOverCallback = [];
	}

	void start() {
		this.inTern = true;
		this.gameTimer.start();
	}

	void setCallbacks(TurnChangeCallback tcc, GOverCallback goc) {
		this.turnChangeCallback ~= tcc;
		this.gOverCallback ~= goc;
	}

	bool getInTern() {
		return this.inTern;
	}
	void show(FieldShow callback) {
		foreach (int y, Quantum[] line; this.field) {
			foreach (int x, Quantum q; line) {
				callback(new Pos(x, y), q);
			}
		}
	}
	void showInHand(bool side, void delegate(Quantum q) callback) {
		Quantum[] inHand = side ? this.inHandT : this.inHandF;
		foreach (q; inHand) {
			callback(q);
		}
	}

	Quantum get(Pos at) {
		return this.field[at._y][at._x];
	}

	Quantum getInHand(bool side, int at) {
		Quantum[] list = side ? this.inHandT : this.inHandF;
		if (at < 0 || at >= list.length) {
			return null;
		}
		return list[at];
	}

	void aHandPut(bool side, Quantum q, Pos to) {
		auto action = q.putOn.prepare(to);
		if (this.inTern != side) throw new Exception("Not your turn");
		if (q.side != side) throw new Exception("Not your piece");
		if (q.pos !is null) throw new Exception("Not in hand");
		if (this.get(to) !is null) throw new Exception("Not empty");
		if (! action.can()) throw new Exception("Can't put on ...");

		if (side) {
			if (! contains(this.inHandT, q)) throw new Exception("Not in in-hand list");
			this.inHandT = this.inHandT.filter!((qq) => qq != q).array;
		} else {
			if (! contains(this.inHandF, q)) throw new Exception("Not in in-hand list");
			this.inHandF = this.inHandF.filter!((qq) => qq != q).array;
		}

		this.field[to._y][to._x] = q;
		action.doit();

		this.turnChange();
	}

	bool aHandStep(bool side, Pos from, Pos to, bool delegate() listenReface) {
		Quantum q = this.get(from);
		if (q is null) throw new Exception("No piece exists");
		auto action = q.move.prepare(to);
		if (this.inTern != side) throw new Exception("Not your turn");
		if (q.side != side) throw new Exception("Not your piece");
		if (! q.pos.equals(from)) throw new Exception("XX Conflict XX");
		if (! action.can()) throw new Exception("Can't move-to ...");
		if (this._somethingInside(from, to)) throw new Exception("Cant' straddle another piece");

		Quantum toInHand = this.get(to);
		if (toInHand !is null) {
			Quantum[] inHand = side ? this.inHandT : this.inHandF;
			if (toInHand.side == side) {
				throw new Exception("Taking self...");
			}
			toInHand.pos = null;
			toInHand.side = side;
			toInHand.face = 0;
			toInHand.possibility = toInHand.possibility.remove!((p) => p == PieceType.ou);

			toInHand.listener(toInHand, [PieceType.ou]);

			(side ? this.inHandT : this.inHandF) ~= toInHand;
		}

		action.doit();
		this.field[from._y][from._x] = null;
		this.field[to._y][to._x] = q;
		if ((_isEdge(side, from) || _isEdge(side, to)) && q.reface.prepare(Void._).can()) {
			if (listenReface()) {
				q.reface.prepare(Void._).doit();
			}
		}

		Origin originRival = side ? this.originF : this.originT;
		bool result = ! originRival.pieces.canFind!((q) {
			return contains(q.possibility, PieceType.ou);
		});
		if (result) {
			foreach(goc; this.gOverCallback) {
				goc(side);
			}
		} else {
			this.turnChange();
		}
		return result;
	}

	void turnChange() {
		this.gameTimer.switchOff();
		this.inTern = ! this.inTern;
		foreach (tcc; this.turnChangeCallback) {
			tcc(this.inTern);
		}
		this.gameTimer.switchOn();
	}

	bool _somethingInside(Pos from, Pos to) {
		int dy = to._y - from._y;
		int dx = to._x - from._x;
		int ady = abs(dy);
		int adx = abs(dx);
		if ((ady <= 1 && adx <= 1)
			|| (adx == 1 && ady == 2)) return false;
		int big = max(adx, ady);
		foreach (i; 1..big) {
			int x = from._x + (dx / big * i);
			int y = from._y + (dy / big * i);

			if (this.get(new Pos(x, y))) return true;
		}
		return false;
	}

	Remains getRemains() {
		auto remains = this.gameTimer.showRemains();
		if (remains.winner == Side.None) {
			if (remains.timeT.remain < 0.msecs) {
				foreach (cb; gOverCallback) {
					cb(false);
				}
				remains.winner = Side.False;
			} else if (remains.timeF.remain < 0.msecs) {
				foreach (cb; gOverCallback) {
					cb(true);
				}
				remains.winner = Side.True;
			}
		}
		return remains;
	}
}

bool _isEdge(bool side, Pos pos) {
	int[] edgeLine;
	if (side) {
		edgeLine = [0, 1, 2];
	} else {
		edgeLine = [8, 7, 6];
	}
	return contains(edgeLine, pos._y);
}


unittest {
	Pos p(int x, int y) { return new Pos(x, y); }
	void _moveTo(Server server, bool side, Pos from, int dx, int dy, bool reface) {
		Pos to = p(from._x + dx, from._y + dy);
		server.aHandStep(side, from, to, () => reface);
		from._x = to._x;
		from._y = to._y;
	}
	{
		// お互いに取り合うテスト(手駒確認)
		Server server = new Server(newTimer(99,99));
		assert(! server.aHandStep(
							true,
							p(0, 6),
							p(0, 2),
							() => false),
						"Step 1st");
		assert(server.inHandT.length == 1, "inhand t");
		assert(! server.aHandStep(
							false,
							p(1, 2),
							p(1, 6),
							() => true),
						"Step 2nd");
		assert(server.inHandT.length == 1, "inhand t");
		assert(server.inHandF.length == 1, "inhand f");
	}
	{
		// とりとめもなく動くテスト
		Server server = new Server(newTimer(99,99));
		assert(! server.aHandStep(
				true,
				p(0, 6),
				p(0, 5),
				() => false),
			"Step 1st");
		assert(! server.aHandStep(
				false,
				p(1, 2),
				p(1, 3),
				() => false),
			"Step 2nd");
		assert(! server.aHandStep(
				true,
				p(0, 5),
				p(0, 4),
				() => false),
			"Step 3rd");
		assert(! server.aHandStep(
				false,
				p(1, 3),
				p(1, 4),
				() => false),
			"Step 4th");
		assert(server.inHandT.length == 0, "inhand t");
		assert(server.inHandF.length == 0, "inhand f");
	}
	{
		Server server = new Server(newTimer(99,99));
		assert(! server.aHandStep(
				true,
				new Pos(0, 6),
				new Pos(0, 2),
				() => false),
			"Step 1st");
		Quantum qInHand = server.get(new Pos(0, 2));
		assert(! server.aHandStep(
				false,
				new Pos(1, 2),
				new Pos(0, 2),
				() => false),
			"Step 2nd take");
		assert(! server.aHandStep(
				true,
				new Pos(1, 6),
				new Pos(1, 5),
				() => false),
			"Step 3rd");
		server.aHandPut(
				false,
				qInHand,
				new Pos(4, 4));
		assert(! server.aHandStep(
				true,
				new Pos(2, 6),
				new Pos(2, 5),
				() => false),
			"Step 5th");
		assert(! server.aHandStep(
				false,
				new Pos(4, 4),
				new Pos(6, 4),
				() => false),
			"Step 6th as hi");
		bool[] boolList = server.originT.pieces.map!((q) {
			return ((q.possibility.length == 1
					&& q.possibility[0] == PieceType.hi
					&& q.side == false)
				|| (! contains(q.possibility, PieceType.hi))
			);
		}).array;
		assert(boolList.reduce!((a, b) => a && b), "true side no hi");
		assert(server.inHandT.length == 1, "inhand t");
		assert(server.inHandF.length == 0, "inhand f");
	}
	{
		// Finish 1 (<gin or ou>から成銀によってouが確定)
		Server server = new Server(newTimer(99,99));
		bool isFinished = false;
		server.setCallbacks((a) {}, (b) { isFinished = true; });
		Pos[] allPos = [
			p(0,6),p(1,6),p(2,6)	// gin, gin, ou
		];

		Pos pRiv = p(1, 1);
		foreach (pos; allPos) {
			_moveTo(server, true, pos, 1, -1, false);
			_moveTo(server, false, pRiv, 1, 0, false);
		}
		foreach (pos; allPos) {
			_moveTo(server, true, pos, -1, 1, false);
			_moveTo(server, false, pRiv, -1, 0, false);
		}
		foreach(i; 0..3) {
			foreach (pos; allPos) {
				_moveTo(server, true, pos, 0, -1, false);
				if (i % 2 == 0) {
					_moveTo(server, false, pRiv, 1, 0, false);
				} else {
					_moveTo(server, false, pRiv, -1, 0, false);
				}
			}
		}
		_moveTo(server, true, allPos[0], 0, -1, true);
		assert(! isFinished, "Refece to become gin");
		_moveTo(server, false, pRiv, 1, 0, false);

		_moveTo(server, true, allPos[1], 0, -1, true);
		assert(! isFinished, "Refece to become gin");
		_moveTo(server, false, p(2, 2), 0, 1, false);
		assert(isFinished, "Remains is ou");
	}
	{
		// Finish 2 (<gin or ou>から銀が取られてouが確定)
		Server server = new Server(newTimer(99,99));
		bool isFinished = false;
		server.setCallbacks((a) {}, (b) { isFinished = true; });
		Pos[] allPos = [
			p(0,6),p(1,6),p(2,6)	// gin, gin, ou
		];

		Pos pRiv = p(1, 1);
		foreach (pos; allPos) {
			_moveTo(server, true, pos, 1, -1, false);
			_moveTo(server, false, pRiv, 1, 0, false);
		}
		foreach (pos; allPos) {
			_moveTo(server, true, pos, -1, 1, false);
			_moveTo(server, false, pRiv, -1, 0, false);
		}
		foreach (pos; allPos[0..2]) {
			_moveTo(server, true, pos, 0, -1, false);  // step forward...not kk
			_moveTo(server, false, p(pos._x, 2), 0, 3, false);  // taken.
		}
		auto toOu = allPos[2];
		_moveTo(server, true, toOu, 0, -1, false);  // step forward...not kk

		assert(server.inHandF.length == 2, "TWO gin both in hand");
		assert(server.inHandF.map!(q => q.possibility).array == [[PieceType.gin],[PieceType.gin]], "two GIN both in hand");
		auto maybeOu = server.get(toOu);

		assert(maybeOu.possibility == [PieceType.ou], "Must be ou");
		assert(! isFinished, "Still not taken");
		_moveTo(server, false, p(toOu._x, 2), 0, 3, false);  // taken
		assert(isFinished, "Ou has taken");
	}
}
