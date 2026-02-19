const std = @import("std");
const termenv = @import("termenv");

const Color = enum(u3) {
    Red,
    Magenta,
    Yellow,
    Green,
    Blue,
    Orange,
    Cyan,

    Empty,
};

const FigureType = enum(u3) {
    I,
    O,
    L,
    J,
    S,
    Z,
    T,
};

const RotTry = enum(u3) {
    Can,
    Cannot,
    MoveLeft,
    MoveRight,
    MoveLeftTwice,
    MoveRightTwice,
};

const Rotation = u2;

const Position = @Vector(4, i16);

const Prng = struct {
    a: u32,

    pub fn init() Prng {
        var seed: u32 = 1234567890;
        std.posix.getrandom(std.mem.asBytes(&seed)) catch {};
        return Prng{ .a = seed };
    }
    pub fn next(self: *Prng) u32 {
        var x = self.a;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.a = x;
        return x;
    }

    pub fn rand(self: *Prng, comptime T: type) T {
        var x: u3 = @truncate(self.next());
        while (x == 7) {
            x = @truncate(self.next());
        }

        return @as(T, @enumFromInt(x));
    }
};

const RowsArray = struct {
    indices: [4]?usize,

    pub fn init() RowsArray {
        return RowsArray{ .indices = .{ null, null, null, null } };
    }

    pub fn add(self: *RowsArray, row: usize) void {
        for (0..4) |i| {
            const r = self.indices[i];
            if (r == null) {
                self.indices[i] = row;
                break;
            }
        }
    }
};

const Figure = struct {
    shape: FigureType,
    color: Color,
    rot: Rotation,
    buffer: Position,

    pub fn init(w: i16, t: FigureType, r: Rotation) Figure {
        const a: Color = @enumFromInt(@intFromEnum(t));
        const mid: i16 = @divFloor(w, 2) - 1;
        const buf: Position = switch (t) {
            .I => Position{ mid - 4 * w, mid - 3 * w, mid - 2 * w, mid - w },
            .O => Position{ mid - 2 * w, mid - 2 * w + 1, mid - w, mid - w + 1 },
            .L => Position{ mid - 3 * w, mid - 2 * w, mid - w, mid - w + 1 },
            .J => Position{ mid - 3 * w, mid - 2 * w, mid - w - 1, mid - w },
            .S => Position{ mid - 2 * w, mid - 2 * w + 1, mid - w - 1, mid - w },
            .Z => Position{ mid - 2 * w - 1, mid - 2 * w, mid - w, mid - w + 1 },
            .T => Position{ mid - 2 * w - 1, mid - 2 * w, mid - 2 * w + 1, mid - w },
        };

        var fig = Figure{
            .shape = t,
            .color = a,
            .rot = 0,
            .buffer = buf,
        };
        fig.rotate(w, r);

        return fig;
    }

    fn rotate(self: *Figure, w: i16, r: Rotation) void {
        const steps: usize = r -% self.rot;
        for (0..steps) |_| {
            const new_pos: Position = self.try_rotate_once(w);
            self.buffer = new_pos;
            self.rot +%= 1;
        }
    }

    pub fn try_rotate_once(self: *const Figure, w: i16) Position {
        var new_buffer: Position = undefined;
        switch (self.rot) {
            0 => {
                switch (self.shape) {
                    .I => new_buffer = .{ self.buffer[1] - 1, self.buffer[1], self.buffer[1] + 1, self.buffer[1] + 2 },
                    .L => new_buffer = .{ self.buffer[1] - 1, self.buffer[1], self.buffer[1] + 1, self.buffer[2] - 1 },
                    .J => new_buffer = .{ self.buffer[0] - 1, self.buffer[1] - 1, self.buffer[1], self.buffer[1] + 1 },
                    .S => new_buffer = .{ self.buffer[0] - w - 1, self.buffer[0] - 1, self.buffer[0], self.buffer[3] },
                    .Z => new_buffer = .{ self.buffer[1] - w + 1, self.buffer[1], self.buffer[1] + 1, self.buffer[2] },
                    .T => new_buffer = .{ self.buffer[1] - w, self.buffer[0], self.buffer[1], self.buffer[3] },
                    .O => new_buffer = self.buffer,
                }
            },
            1 => {
                switch (self.shape) {
                    .I => new_buffer = .{ self.buffer[2] - w, self.buffer[2], self.buffer[2] + w, self.buffer[2] + 2 * w },
                    .L => new_buffer = .{ self.buffer[0] - w, self.buffer[1] - w, self.buffer[1], self.buffer[1] + w },
                    .J => new_buffer = .{ self.buffer[0] + 1, self.buffer[0] + 2, self.buffer[2], self.buffer[2] + w },
                    .S => new_buffer = .{ self.buffer[2], self.buffer[2] + 1, self.buffer[3] - 1, self.buffer[3] },
                    .Z => new_buffer = .{ self.buffer[1] - 1, self.buffer[1], self.buffer[3], self.buffer[3] + 1 },
                    .T => new_buffer = .{ self.buffer[0], self.buffer[1], self.buffer[2], self.buffer[2] + 1 },
                    .O => new_buffer = self.buffer,
                }
            },
            2 => {
                switch (self.shape) {
                    .I => new_buffer = .{ self.buffer[2] - 2, self.buffer[2] - 1, self.buffer[2], self.buffer[2] + 1 },
                    .L => new_buffer = .{ self.buffer[1] + 1, self.buffer[2] - 1, self.buffer[2], self.buffer[2] + 1 },
                    .J => new_buffer = .{ self.buffer[2] - 1, self.buffer[2], self.buffer[2] + 1, self.buffer[3] + 1 },
                    .S => new_buffer = .{ self.buffer[0] - w - 1, self.buffer[0] - 1, self.buffer[0], self.buffer[3] },
                    .Z => new_buffer = .{ self.buffer[1] - w + 1, self.buffer[1], self.buffer[1] + 1, self.buffer[2] },
                    .T => new_buffer = .{ self.buffer[0], self.buffer[2], self.buffer[3], self.buffer[2] + w },
                    .O => new_buffer = self.buffer,
                }
            },
            3 => {
                switch (self.shape) {
                    .I => new_buffer = .{ self.buffer[1] - 2 * w, self.buffer[1] - w, self.buffer[1], self.buffer[1] + w },
                    .L => new_buffer = .{ self.buffer[0] - 1, self.buffer[2], self.buffer[2] + w, self.buffer[3] + w },
                    .J => new_buffer = .{ self.buffer[1] - w, self.buffer[1], self.buffer[3] - 2, self.buffer[3] - 1 },
                    .S => new_buffer = .{ self.buffer[2], self.buffer[2] + 1, self.buffer[3] - 1, self.buffer[3] },
                    .Z => new_buffer = .{ self.buffer[1] - 1, self.buffer[1], self.buffer[3], self.buffer[3] + 1 },
                    .T => new_buffer = .{ self.buffer[1] - 1, self.buffer[1], self.buffer[2], self.buffer[3] },
                    .O => new_buffer = self.buffer,
                }
            },
        }
        return new_buffer;
    }
};

pub const Game = struct {
    x: i32,
    y: i32,
    w: i32,
    h: i32,
    buffer: []Color,
    bitset: []u1,
    rand: Prng,
    figure: Figure,
    shadow: Position,
    next: Figure,

    pub fn init(x: u32, y: u32, width: u32, height: u32) !Game {
        const cells = try termenv.allocator.alloc(Color, width * height);
        const bits = try termenv.allocator.alloc(u1, width * height);

        var pr = Prng.init();
        const fig = Figure.init(@intCast(width), pr.rand(FigureType), @truncate(pr.next()));
        const next = Figure.init(@intCast(width), pr.rand(FigureType), @truncate(pr.next()));

        @memset(cells, .Empty);
        @memset(bits, 0);

        var game = Game{ .x = @intCast(x), .y = @intCast(y), .w = @intCast(width), .h = @intCast(height), .buffer = cells, .bitset = bits, .rand = pr, .figure = fig, .shadow = undefined, .next = next };
        game.update_shadow();
        return game;
    }

    pub fn deinit(self: *Game) void {
        termenv.allocator.free(self.buffer);
        termenv.allocator.free(self.bitset);
    }

    fn clear_screen(self: *Game) !void {
        _ = self;
        _ = try termenv.stdout.write("\x1b[1;1H\x1b[0m\x1b[J");
        try termenv.stdout.flush();
    }

    fn draw_figure(self: *Game) !void {
        const color_code: i32 = switch (self.figure.color) {
            .Red => 41,
            .Green => 42,
            .Yellow => 43,
            .Blue => 44,
            .Magenta => 45,
            .Cyan => 46,
            .Orange => 101,
            .Empty => 40,
        };
        const arr: [4]i16 = self.figure.buffer;
        for (arr) |i| {
            if (i >= 0) {
                const row = self.y + 2 + @divFloor(i, self.w);
                const col = 2 * (self.x + 1) + 1 + 2 * (@mod(i, self.w));
                try termenv.stdout.print("\x1b[{};{}H\x1b[{}m  ", .{ row, col, color_code });
            }
        }
        _ = try termenv.stdout.write("\x1b[0m");
        try termenv.stdout.flush();
    }
    fn draw_shadow(self: *Game) !void {
        const color_code: i32 = switch (self.figure.color) {
            .Red => 41,
            .Green => 42,
            .Yellow => 43,
            .Blue => 44,
            .Magenta => 45,
            .Cyan => 46,
            .Orange => 101,
            .Empty => unreachable,
        };
        const arr: [4]i16 = self.shadow;
        for (arr) |i| {
            if (i >= 0) {
                const row = self.y + 2 + @divFloor(i, self.w);
                const col = 2 * (self.x + 1) + 1 + 2 * (@mod(i, self.w));
                try termenv.stdout.print("\x1b[{};{}H\x1b[{}m░░", .{ row, col, color_code });
            }
        }
        _ = try termenv.stdout.write("\x1b[0m");
        try termenv.stdout.flush();
    }
    fn draw_next(self: *Game) !void {
        var min_x: i32 = std.math.maxInt(i32);
        var max_x: i32 = 0;
        var min_y: i32 = std.math.maxInt(i32);
        var max_y: i32 = 0;
        const w: i16 = @intCast(self.w);
        const arr: [4]i16 = self.next.buffer + @as(Position, @splat(4 * w));
        for (arr) |i| {
            const row: i16 = @divFloor(i, w);
            const col: i16 = @rem(i, w);
            min_x = @min(min_x, col);
            max_x = @max(max_x, col);
            min_y = @min(min_y, row);
            max_y = @max(max_y, row);
        }
        var left = self.x + self.w + 2 + 2;
        if (max_x - min_x <= 1) {
            left += 1;
        }
        var top = self.y + 5;
        if (max_y - min_y <= 1) {
            top += 1;
        }
        const color_code: i32 = switch (self.next.color) {
            .Red => 41,
            .Green => 42,
            .Yellow => 43,
            .Blue => 44,
            .Magenta => 45,
            .Cyan => 46,
            .Orange => 101,
            .Empty => 40,
        };
        for (arr) |i| {
            const row = @divFloor(i, w);
            const col = @rem(i, w);
            try termenv.stdout.print("\x1b[{};{}H\x1b[{}m  ", .{ row + top - min_y, 2 * (col - min_x + left), color_code });
        }
        _ = try termenv.stdout.write("\x1b[0m");
        try termenv.stdout.flush();
    }

    pub fn draw(self: *Game) !void {
        try self.clear_screen();

        const w: u32 = @intCast(self.w);
        const h: u32 = @intCast(self.h);

        try termenv.stdout.print("\x1b[{};{}H ▄", .{ self.y + 1, 2 * self.x + 1 });
        for (0..@intCast(self.w)) |_| {
            _ = try termenv.stdout.write("▄▄");
        }
        _ = try termenv.stdout.write("▄");

        for (0..h) |i| {
            try termenv.stdout.print("\x1b[{};{}H █", .{ self.y + 2 + @as(i32, @intCast(i)), 2 * self.x + 1 });
            for (0..w) |j| {
                const index = i * w + j;
                const cell = self.buffer[index];

                switch (cell) {
                    .Red => {
                        _ = try termenv.stdout.write("\x1b[41m  ");
                    },
                    .Green => {
                        _ = try termenv.stdout.write("\x1b[42m  ");
                    },
                    .Yellow => {
                        _ = try termenv.stdout.write("\x1b[43m  ");
                    },
                    .Blue => {
                        _ = try termenv.stdout.write("\x1b[44m  ");
                    },
                    .Magenta => {
                        _ = try termenv.stdout.write("\x1b[45m  ");
                    },
                    .Cyan => {
                        _ = try termenv.stdout.write("\x1b[46m  ");
                    },
                    .Orange => {
                        _ = try termenv.stdout.write("\x1b[101m  ");
                    },
                    .Empty => {
                        _ = try termenv.stdout.write("\x1b[40m  ");
                    },
                }
            }
            _ = try termenv.stdout.write("█\x1b[0m");
            try termenv.stdout.flush();
        }

        try termenv.stdout.print("\x1b[{};{}H ▀", .{ self.y + 1 + self.h + 1, 2 * self.x + 1 });
        for (0..@intCast(self.w)) |_| {
            _ = try termenv.stdout.write("▀▀");
        }
        _ = try termenv.stdout.write("▀ ");

        try self.draw_shadow();
        try self.draw_figure();
        try self.draw_next();

        try termenv.stdout.print("\x1b[{};1H ", .{self.y + self.h + 3});
        try termenv.stdout.flush();
    }

    fn new_figure(self: *Game) void {
        const next = Figure.init(@intCast(self.w), self.rand.rand(FigureType), @truncate(self.rand.next()));
        self.figure = self.next;
        self.next = next;
        self.update_shadow();
    }
    fn update_shadow(self: *Game) void {
        var pos = self.figure.buffer;
        const lower = @as(Position, @splat(@as(i16, @intCast(self.w))));
        loop: while (true) : (pos += lower) {
            const arr: [4]i16 = pos;
            for (arr) |ind| {
                if (ind < 0) {
                    continue;
                }
                if (ind >= self.bitset.len or self.bitset[@intCast(ind)] == 1) {
                    self.shadow = pos - lower;
                    break :loop;
                }
            }
        }
    }
    fn add_to_bitset(self: *Game) bool {
        const arr: [4]i16 = self.figure.buffer;
        for (arr) |i| {
            if (i < 0) {
                return false;
            }
            const ind: usize = @intCast(i);
            self.bitset[ind] = 1;
            self.buffer[ind] = self.figure.color;
        }
        return true;
    }
    fn clear_rows(self: *Game) void {
        var rows = RowsArray.init();
        var i: isize = self.h - 1;
        while (i >= 0) : (i -= 1) {
            const n: usize = @intCast(i);
            var filled = true;
            const starting_index = n * @as(usize, @intCast(self.w));
            const arr = self.bitset[starting_index .. starting_index + @as(usize, @intCast(self.w))];
            for (arr) |j| {
                if (j == 0) {
                    filled = false;
                    break;
                }
            }
            if (filled) {
                rows.add(n);
            }
        }

        i = 0;
        while (i < 4) : (i += 1) {
            const n: usize = @intCast(i);
            if (rows.indices[n] == null) {
                break;
            }
            const ind = (rows.indices[n].? + n) * @as(usize, @intCast(self.w));
            @memmove(self.bitset[@as(usize, @intCast(self.w)) .. ind + @as(usize, @intCast(self.w))], self.bitset[0..ind]);
            @memmove(self.buffer[@as(usize, @intCast(self.w)) .. ind + @as(usize, @intCast(self.w))], self.buffer[0..ind]);
        }
    }
    fn should_place(self: *Game) bool {
        const arr: [4]i16 = self.figure.buffer;
        for (arr) |i| {
            const lower = i + self.w;
            if (lower < 0) continue;
            if (lower >= self.bitset.len or self.bitset[@intCast(lower)] == 1) {
                return true;
            }
        }
        return false;
    }
    fn place_figure(self: *Game) bool {
        const added = self.add_to_bitset();
        if (!added) {
            return false;
        }

        self.clear_rows();
        self.new_figure();
        return true;
    }
    pub fn move_left(self: *Game) bool {
        defer self.update_shadow();

        //Check left border and other blocks
        var near_border = false;
        var would_collide = false;
        const arr: [4]i16 = self.figure.buffer;
        for (arr) |i| {
            const col = @rem(i, self.w);
            if (col == 0) {
                near_border = true;
                break;
            }
            if (i >= 0 and self.bitset[@intCast(i - 1)] == 1) {
                would_collide = true;
                break;
            }
        }

        if (!near_border and !would_collide) {
            //Move left
            const shift: Position = @splat(-1);
            self.figure.buffer += shift;
        }

        const placed = self.should_place();
        if (placed) {
            return self.place_figure();
        }

        return true;
    }
    pub fn move_right(self: *Game) bool {
        defer self.update_shadow();

        //Check right border and other blocks
        var near_border = false;
        var would_collide = false;
        const arr: [4]i16 = self.figure.buffer;
        for (arr) |i| {
            const col = @rem(i, self.w);
            if (col == self.w - 1) {
                near_border = true;
                break;
            }
            if (i >= 0 and i < self.bitset.len - 1 and self.bitset[@intCast(i + 1)] == 1) {
                would_collide = true;
                break;
            }
        }

        if (!near_border and !would_collide) {
            //Move right
            const shift: Position = @splat(1);
            self.figure.buffer += shift;
        }

        const placed = self.should_place();
        if (placed) {
            return self.place_figure();
        }

        return true;
    }
    pub fn place_down(self: *Game) bool {
        const shw: [4]i16 = self.shadow;
        const fig: [4]i16 = self.figure.buffer;
        const to_move: i16 = @divExact(shw[0] - fig[0], @as(i16, @intCast(self.w)));
        for (0..@intCast(to_move)) |_| {
            const res = self.move_down();
            if (!res) {
                return false;
            }
        }
        return true;
    }
    pub fn move_down(self: *Game) bool {
        const placed = self.should_place();
        if (placed) {
            return self.place_figure();
        }

        const shift: Position = @splat(@intCast(self.w));
        self.figure.buffer += shift;

        return true;
    }
    fn can_collide(self: *Game, new_pos: Position) bool {
        const arr: [4]i16 = new_pos;
        for (arr) |i| {
            if (i < 0 or i >= self.bitset.len) {
                continue;
            }
            if (self.bitset[@intCast(i)] == 1) {
                return true;
            }
        }
        return false;
    }
    fn borders_rotation(self: *Game, new_pos: Position) RotTry {
        var left = false;
        var right = false;
        const arr: [4]i16 = new_pos;
        for (arr) |i| {
            const col = @rem(i, self.w);
            if (col == 0) {
                left = true;
            } else if (col == self.w - 1) {
                right = true;
            }
            if (i >= self.buffer.len) {
                return .Cannot;
            }
        }
        if (left and right) {
            const buf: [4]i16 = self.figure.buffer;
            const middle: i32 = @divFloor(self.w, 2);
            var left_half: i32 = 0;
            var right_half: i32 = 0;
            for (buf) |i| {
                const col = @rem(i, self.w);
                if (col < middle) {
                    left_half += 1;
                } else {
                    right_half += 1;
                }
            }
            if (left_half > right_half) {
                if (self.figure.rot == 2) {
                    return .MoveRightTwice;
                }
                return .MoveRight;
            } else {
                if (self.figure.rot == 0) {
                    return .MoveLeftTwice;
                }
                return .MoveLeft;
            }
        } else {
            return .Can;
        }
    }
    pub fn rotate_figure(self: *Game) bool {
        defer self.update_shadow();

        const new_pos: Position = self.figure.try_rotate_once(@intCast(self.w));
        const borders = self.borders_rotation(new_pos);

        var to_try: Position = undefined;

        switch (borders) {
            .Can => {
                to_try = new_pos;
            },
            .Cannot => {
                return true;
            },
            .MoveLeft => {
                const shifted: Position = self.figure.buffer + @as(Position, @splat(-1));
                const fig = Figure{ .buffer = shifted, .color = self.figure.color, .rot = self.figure.rot, .shape = self.figure.shape };
                to_try = fig.try_rotate_once(@intCast(self.w));
            },
            .MoveRight => {
                const shifted: Position = self.figure.buffer + @as(Position, @splat(1));
                const fig = Figure{ .buffer = shifted, .color = self.figure.color, .rot = self.figure.rot, .shape = self.figure.shape };
                to_try = fig.try_rotate_once(@intCast(self.w));
            },
            .MoveLeftTwice => {
                const shifted: Position = self.figure.buffer + @as(Position, @splat(-2));
                const fig = Figure{ .buffer = shifted, .color = self.figure.color, .rot = self.figure.rot, .shape = self.figure.shape };
                to_try = fig.try_rotate_once(@intCast(self.w));
            },
            .MoveRightTwice => {
                const shifted: Position = self.figure.buffer + @as(Position, @splat(2));
                const fig = Figure{ .buffer = shifted, .color = self.figure.color, .rot = self.figure.rot, .shape = self.figure.shape };
                to_try = fig.try_rotate_once(@intCast(self.w));
            },
        }

        const collision = self.can_collide(to_try);
        if (!collision) {
            self.figure.buffer = to_try;
            self.figure.rot +%= 1;
        }

        return true;
    }
};
