const std = @import("std");

var fdin: std.posix.fd_t = undefined;
var original: std.posix.termios = undefined;

var win_width: u32 = undefined;
var win_heigth: u32 = undefined;

var stdout_buffer: [2048]u8 = undefined;
var stdout_writer: std.fs.File.Writer = undefined;
var stdout: *std.io.Writer = undefined;

var keys_buffer: [16]u8 = undefined;
var keys_list: KeysArray = undefined;

var time: Timing = undefined;

var alloc_buffer: [2048]u8 = undefined;
var gpa: std.heap.FixedBufferAllocator = undefined;
var allocator: std.mem.Allocator = undefined;

pub const Key = enum(u3) {
    Up,
    Down,
    Left,
    Right,
    Q,
    P,
    Space,

    Undefined,
};

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

const Rotation = u2;

const RotTry = enum(u3) {
    Can,
    Cannot,
    MoveLeft,
    MoveRight,
    MoveLeftTwice,
    MoveRightTwice,
};

const KeysArray = struct {
    items: [8]Key,
    len: usize,

    pub fn add(self: *KeysArray, key: Key) void {
        self.items[self.len] = key;
        self.len += 1;
    }

    pub fn reset(self: *KeysArray) void {
        self.len = 0;
    }
};

const Timing = struct {
    target: f32,
    last_time: f32,

    pub fn set_target(self: *Timing, seconds: f32) void {
        self.target = seconds;
    }

    pub fn get_time(self: *Timing) !f32 {
        _ = self;
        const ins: std.time.Instant = try std.time.Instant.now();
        const spec: std.posix.timespec = ins.timestamp;
        return @as(f32, @floatFromInt(spec.sec)) + @as(f32, @floatFromInt(spec.nsec)) / 1000000000.0;
    }

    pub fn wait_time(self: *Timing, seconds: f32) void {
        _ = self;
        if (seconds < 0) {
            return;
        }
        const sec = @floor(seconds);
        const nsec: u64 = @intFromFloat((seconds - sec) * 1_000_000_000.0);
        std.posix.nanosleep(@intFromFloat(sec), nsec);
    }
};

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

fn set_allocator() void {
    gpa = std.heap.FixedBufferAllocator.init(alloc_buffer[0..]);
    const alloc = gpa.allocator();
    allocator = alloc;
}

fn get_console_size(fd: std.posix.fd_t) void {
    var winstruct: std.posix.winsize = undefined;
    _ = std.posix.system.ioctl(fd, std.posix.T.IOCGWINSZ, @intFromPtr(&winstruct));
    win_width = winstruct.col;
    win_heigth = winstruct.row;
}

fn set_nonblocking_mode(fd: std.posix.fd_t) !std.posix.termios {
    const termios: std.posix.termios = try std.posix.tcgetattr(fd);
    var raw: std.posix.termios = termios;
    raw.lflag.ECHO = false;
    raw.lflag.ICANON = false;
    try std.posix.tcsetattr(fd, std.posix.TCSA.NOW, raw);
    const flags = try std.posix.fcntl(fd, std.posix.F.GETFL, 0);
    const nonblock: usize = 1 << @bitOffsetOf(std.posix.O, "NONBLOCK");
    _ = try std.posix.fcntl(fd, std.posix.F.SETFL, flags | nonblock);
    return termios;
}

fn reset_nonblocking_mode(fd: std.posix.fd_t, termios: *std.posix.termios) !void {
    const flags = try std.posix.fcntl(fd, std.posix.F.GETFL, 0);
    const nonblock: usize = 1 << @bitOffsetOf(std.posix.O, "NONBLOCK");
    _ = try std.posix.fcntl(fd, std.posix.F.SETFL, flags & (~nonblock));
    termios.lflag.ECHO = true;
    termios.lflag.ICANON = true;
    try std.posix.tcsetattr(fd, std.posix.TCSA.NOW, termios.*);
}

fn set_terminal_styling() !void {
    _ = try stdout.write("\x1b[5 q");
    try stdout.flush();
}

fn reset_terminal_styling() !void {
    // _ = try stdout.write("\x1b[0m\x1b[1;1H\x1b[J\x1b[0 q");
    _ = try stdout.write("\x1b[0m\x1b[0 q");
    try stdout.flush();
}

fn sleeptime(seconds: f32) void {
    const sec = @floor(seconds);
    const nsec: u64 = @intFromFloat((seconds - sec) * 1_000_000_000.0);
    std.posix.nanosleep(@intFromFloat(sec), nsec);
}

fn zero_keys_buffer() void {
    @memset(&keys_buffer, 0);
}

fn get_keys(buffer: *const [16]u8) void {
    var read: u32 = 0;

    while (true) {
        switch (buffer[read]) {
            27 => {
                switch (buffer[read + 1]) {
                    91 => {
                        switch (buffer[read + 2]) {
                            65 => {
                                keys_list.add(.Up);
                                read += 3;
                            },
                            66 => {
                                keys_list.add(.Down);
                                read += 3;
                            },
                            67 => {
                                keys_list.add(.Right);
                                read += 3;
                            },
                            68 => {
                                keys_list.add(.Left);
                                read += 3;
                            },
                            else => {
                                read += 3;
                            },
                        }
                    },
                    else => {},
                }
            },
            32 => {
                keys_list.add(.Space);
                read += 1;
            },
            112 => {
                keys_list.add(.P);
                read += 1;
            },
            113 => {
                keys_list.add(.Q);
                read += 1;
            },
            0 => {
                break;
            },
            else => {
                read += 1;
            },
        }
    }
}

pub fn init_terminal() !void {
    fdin = std.posix.STDIN_FILENO;
    get_console_size(std.posix.STDOUT_FILENO);

    stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    stdout = &stdout_writer.interface;

    original = try set_nonblocking_mode(fdin);
    try set_terminal_styling();

    keys_list.reset();

    set_allocator();
}

pub fn deinit_terminal() void {
    reset_nonblocking_mode(fdin, &original) catch {};
    reset_terminal_styling() catch {};
}

pub fn set_target_fps(fps: u32) void {
    time.set_target(1.0 / @as(f32, @floatFromInt(fps)));
}
pub fn get_fall_frames(speed: f32) u32 {
    const fps = 1.0 / time.target;
    return @intFromFloat(fps * speed);
}

pub fn poll_keys() !void {
    zero_keys_buffer();
    keys_list.reset();

    const read = std.posix.read(fdin, &keys_buffer) catch |err| blk: {
        if (err == std.posix.ReadError.WouldBlock) {
            break :blk 0;
        } else {
            return err;
        }
    };
    if (read > 0) {
        get_keys(&keys_buffer);
    }
}

pub fn get_pressed_keys() ![]Key {
    try poll_keys();
    return keys_list.items[0..keys_list.len];
}

pub fn start_loop() !void {
    time.last_time = try time.get_time();
}

pub fn end_frame() !void {
    const current_time = try time.get_time();
    const elapsed = current_time - time.last_time;

    const wait = time.target - elapsed;
    time.wait_time(wait);

    time.last_time = try time.get_time();
}

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

const FigIndices = @Vector(4, i16);

const Figure = struct {
    shape: FigureType,
    color: Color,
    rot: Rotation,
    buffer: FigIndices,

    pub fn init(w: i16, t: FigureType, r: Rotation) Figure {
        const a: Color = @enumFromInt(@intFromEnum(t));
        const mid: i16 = @divFloor(w, 2) - 1;
        const buf: FigIndices = switch (t) {
            .I => FigIndices{ mid - 4 * w, mid - 3 * w, mid - 2 * w, mid - w },
            .O => FigIndices{ mid - 2 * w, mid - 2 * w + 1, mid - w, mid - w + 1 },
            .L => FigIndices{ mid - 3 * w, mid - 2 * w, mid - w, mid - w + 1 },
            .J => FigIndices{ mid - 3 * w, mid - 2 * w, mid - w - 1, mid - w },
            .S => FigIndices{ mid - 2 * w, mid - 2 * w + 1, mid - w - 1, mid - w },
            .Z => FigIndices{ mid - 2 * w - 1, mid - 2 * w, mid - w, mid - w + 1 },
            .T => FigIndices{ mid - 2 * w - 1, mid - 2 * w, mid - 2 * w + 1, mid - w },
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

    pub fn rotate(self: *Figure, w: i16, r: Rotation) void {
        const steps: usize = r -% self.rot;
        for (0..steps) |_| {
            const new_pos: FigIndices = self.try_rotate_once(w);
            self.buffer = new_pos;
            self.rot +%= 1;
        }
    }

    fn try_rotate_once(self: *Figure, w: i16) FigIndices {
        var new_buffer: FigIndices = undefined;
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
    shadow: FigIndices,
    next: Figure,

    pub fn init(x: u32, y: u32, width: u32, height: u32) !Game {
        const cells = try allocator.alloc(Color, width * height);
        const bits = try allocator.alloc(u1, width * height);

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
        allocator.free(self.buffer);
        allocator.free(self.bitset);
    }

    fn clear_screen(self: *Game) !void {
        _ = self;
        _ = try stdout.write("\x1b[1;1H\x1b[0m\x1b[J");
        try stdout.flush();
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
                try stdout.print("\x1b[{};{}H\x1b[{}m  ", .{ row, col, color_code });
            }
        }
        _ = try stdout.write("\x1b[0m");
        try stdout.flush();
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
                try stdout.print("\x1b[{};{}H\x1b[{}m░░", .{ row, col, color_code });
            }
        }
        _ = try stdout.write("\x1b[0m");
        try stdout.flush();
    }
    fn draw_next(self: *Game) !void {
        var min_x: i32 = std.math.maxInt(i32);
        var max_x: i32 = 0;
        var min_y: i32 = std.math.maxInt(i32);
        var max_y: i32 = 0;
        const w: i16 = @intCast(self.w);
        const arr: [4]i16 = self.next.buffer + @as(FigIndices, @splat(4 * w));
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
            try stdout.print("\x1b[{};{}H\x1b[{}m  ", .{ row + top - min_y, 2 * (col - min_x + left), color_code });
        }
        _ = try stdout.write("\x1b[0m");
        try stdout.flush();
    }

    pub fn draw(self: *Game) !void {
        try self.clear_screen();

        const w: u32 = @intCast(self.w);
        const h: u32 = @intCast(self.h);

        try stdout.print("\x1b[{};{}H ▄", .{ self.y + 1, 2 * self.x + 1 });
        for (0..@intCast(self.w)) |_| {
            _ = try stdout.write("▄▄");
        }
        _ = try stdout.write("▄");

        for (0..h) |i| {
            try stdout.print("\x1b[{};{}H █", .{ self.y + 2 + @as(i32, @intCast(i)), 2 * self.x + 1 });
            for (0..w) |j| {
                const index = i * w + j;
                const cell = self.buffer[index];

                switch (cell) {
                    .Red => {
                        _ = try stdout.write("\x1b[41m  ");
                    },
                    .Green => {
                        _ = try stdout.write("\x1b[42m  ");
                    },
                    .Yellow => {
                        _ = try stdout.write("\x1b[43m  ");
                    },
                    .Blue => {
                        _ = try stdout.write("\x1b[44m  ");
                    },
                    .Magenta => {
                        _ = try stdout.write("\x1b[45m  ");
                    },
                    .Cyan => {
                        _ = try stdout.write("\x1b[46m  ");
                    },
                    .Orange => {
                        _ = try stdout.write("\x1b[101m  ");
                    },
                    .Empty => {
                        _ = try stdout.write("\x1b[40m  ");
                    },
                }
            }
            _ = try stdout.write("█\x1b[0m");
            try stdout.flush();
        }

        try stdout.print("\x1b[{};{}H ▀", .{ self.y + 1 + self.h + 1, 2 * self.x + 1 });
        for (0..@intCast(self.w)) |_| {
            _ = try stdout.write("▀▀");
        }
        _ = try stdout.write("▀ ");

        try self.draw_shadow();
        try self.draw_figure();
        try self.draw_next();

        try stdout.print("\x1b[{};1H ", .{self.y + self.h + 3});
        try stdout.flush();
    }

    fn new_figure(self: *Game) void {
        const next = Figure.init(@intCast(self.w), self.rand.rand(FigureType), @truncate(self.rand.next()));
        self.figure = self.next;
        self.next = next;
        self.update_shadow();
    }
    fn update_shadow(self: *Game) void {
        var pos = self.figure.buffer;
        const lower = @as(FigIndices, @splat(@as(i16, @intCast(self.w))));
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
    fn check_borders(self: *Game, dx: i16, dy: i16, x_y: *[2]bool) void {
        const arr: [4]i16 = self.figure.buffer;
        for (arr) |i| {
            const row = @divFloor(i, self.w);
            const col = @mod(i, self.w);
            if ((col == 0 and dx == -1) or (col == self.w - 1 and dx == 1)) {
                x_y[0] = false;
            }
            if (row == self.h - 1 and dy == 1) {
                x_y[1] = false;
            }
        }
    }
    fn check_blocks(self: *Game, dx: FigIndices, dy: FigIndices, x_y: *[2]bool) void {
        const x = self.figure.buffer + dx;
        const arr_x: [4]i16 = x;
        for (arr_x) |i| {
            if (i >= 0) {
                const ind: usize = @intCast(i);
                if (self.bitset[ind] == 1) {
                    x_y[0] = false;
                }
            }
        }
        if (x_y[1]) {
            const y = self.figure.buffer + dy;
            const arr_y: [4]i16 = y;
            for (arr_y) |i| {
                if (i >= 0) {
                    const ind: usize = @intCast(i);
                    if (self.bitset[ind] == 1) {
                        x_y[1] = false;
                    }
                }
            }
        }
    }
    pub fn move_figure(self: *Game, dx: i16, dy: i16) bool {
        const dxvec: FigIndices = @splat(dx);
        const dyvec: FigIndices = @splat(@as(i16, @truncate(dy * self.w)));
        var x_y = [2]bool{ true, true };
        self.check_borders(dx, dy, &x_y);
        self.check_blocks(dxvec, dyvec, &x_y);

        defer self.update_shadow();

        if (x_y[0]) {
            self.figure.buffer += dxvec;
        }
        if (x_y[1]) {
            self.figure.buffer += dyvec;
        } else if (self.add_to_bitset()) {
            self.clear_rows();
            self.new_figure();
        } else {
            return false;
        }
        return true;
    }
    fn check_borders_rotate(self: *Game, new_pos: FigIndices) RotTry {
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
    fn check_blocks_rotate(self: *Game, new_pos: FigIndices) bool {
        const arr: [4]i16 = new_pos;
        for (arr) |i| {
            if (i < 0 or i >= self.bitset.len) {
                continue;
            }
            if (self.bitset[@intCast(i)] == 1) {
                return false;
            }
        }
        return true;
    }
    pub fn rotate_figure(self: *Game) bool {
        const new_pos: FigIndices = self.figure.try_rotate_once(@intCast(self.w));
        const blocks = self.check_blocks_rotate(new_pos);
        const borders = self.check_borders_rotate(new_pos);
        var continued: bool = true;

        defer self.update_shadow();

        if (blocks) {
            var pos: FigIndices = undefined;
            var res: bool = undefined;
            switch (borders) {
                .Can => {
                    continued = true;
                },
                .Cannot => {
                    return continued;
                },
                .MoveLeft => {
                    continued = self.move_figure(-1, 0);
                },
                .MoveRight => {
                    continued = self.move_figure(1, 0);
                },
                .MoveLeftTwice => {
                    continued = self.move_figure(-2, 0);
                },
                .MoveRightTwice => {
                    continued = self.move_figure(2, 0);
                },
            }
            pos = self.figure.try_rotate_once(@intCast(self.w));
            res = self.check_blocks_rotate(pos);
            if (res) {
                self.figure.buffer = pos;
                self.figure.rot +%= 1;
            }
        }

        return continued;
    }
    pub fn place_down(self: *Game) bool {
        const shw: [4]i16 = self.shadow;
        const fig: [4]i16 = self.figure.buffer;
        const to_move: i16 = @divExact(shw[0] - fig[0], @as(i16, @intCast(self.w)));
        return self.move_figure(0, to_move);
    }
};
