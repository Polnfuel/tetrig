const std = @import("std");

var fdin: std.posix.fd_t = undefined;
var original: std.posix.termios = undefined;

pub var win_width: u32 = undefined;
pub var win_heigth: u32 = undefined;

var stdout_buffer: [2048]u8 = undefined;
var stdout_writer: std.fs.File.Writer = undefined;
pub var stdout: *std.io.Writer = undefined;

var keys_buffer: [16]u8 = undefined;
var keys_list: KeysArray = undefined;

var time: Timing = undefined;

var alloc_buffer: [2048]u8 = undefined;
var gpa: std.heap.FixedBufferAllocator = undefined;
pub var allocator: std.mem.Allocator = undefined;

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
    _ = try stdout.write("\x1b[?25l");
    try stdout.flush();
}

fn reset_terminal_styling() !void {
    _ = try stdout.write("\x1b[0m\x1b[?25h");
    try stdout.flush();
}

pub fn sleeptime(seconds: f32) void {
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
