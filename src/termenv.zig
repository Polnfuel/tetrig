const std = @import("std");
const builtin = @import("builtin");

const winspec = @import("winspec");

const windows = std.os.windows;

const os = builtin.os.tag;

var fdin: std.fs.File.Handle = undefined;
var original: Terminal = undefined;

pub var win_width: u32 = undefined;
pub var win_heigth: u32 = undefined;

var stdout_buffer: [4096]u8 = undefined;
var stdout_writer: std.fs.File.Writer = undefined;
pub var stdout: *std.io.Writer = undefined;

var keys_buffer: KeysBuffer = undefined;
var keys_list: KeysArray = undefined;

var time: Timing = undefined;

var alloc_buffer: [2048]u8 = undefined;
var gpa: std.heap.FixedBufferAllocator = undefined;
pub var allocator: std.mem.Allocator = undefined;

const Terminal = if (os == .windows) winspec.WinTerm else std.posix.termios;

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

const KeysBuffer = struct {
    items: [16]u8,
    len: usize,

    pub fn add(self: *KeysBuffer, byte: u8) void {
        self.items[self.len] = byte;
        self.len += 1;
    }

    pub fn reset(self: *KeysBuffer) void {
        self.len = 0;
    }
};

const Timing = struct {
    target: u64,
    last_time: u64,

    pub fn set_target(self: *Timing, nanoseconds: u64) void {
        self.target = nanoseconds;
    }

    pub fn get_time(self: *Timing) !u64 {
        _ = self;
        const ins: std.time.Instant = try std.time.Instant.now();
        switch (os) {
            .windows => {
                const spec: u64 = ins.timestamp;
                return spec;
            },
            else => {
                const spec: std.posix.timespec = ins.timestamp;
                return @intCast(spec.sec * 1_000_000_000 + spec.nsec);
            },
        }
    }

    pub fn wait_time(self: *Timing, nanoseconds: u64) void {
        _ = self;
        std.Thread.sleep(nanoseconds);
    }
};

fn set_allocator() void {
    gpa = std.heap.FixedBufferAllocator.init(alloc_buffer[0..]);
    const alloc = gpa.allocator();
    allocator = alloc;
}

fn get_console_size(fd: std.fs.File.Handle) void {
    if (os == .windows) {
        var winstruct: windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
        _ = windows.kernel32.GetConsoleScreenBufferInfo(fd, &winstruct);
        win_width = @intCast(winstruct.srWindow.Right - winstruct.srWindow.Left + 1);
        win_heigth = @intCast(winstruct.srWindow.Bottom - winstruct.srWindow.Top + 1);
    } else {
        var winstruct: std.posix.winsize = undefined;
        _ = std.posix.system.ioctl(fd, std.posix.T.IOCGWINSZ, @intFromPtr(&winstruct));
        win_width = winstruct.col;
        win_heigth = winstruct.row;
    }
}

fn set_nonblocking_mode(fd: std.fs.File.Handle) !Terminal {
    if (os == .windows) {
        var mode: windows.DWORD = undefined;
        _ = windows.kernel32.GetConsoleMode(fd, &mode);
        const cp = windows.kernel32.GetConsoleOutputCP();
        const orig_mode = mode;
        mode &= ~winspec.ENABLE_ECHO_INPUT;
        mode &= ~winspec.ENABLE_LINE_INPUT;
        mode |= winspec.ENABLE_VIRTUAL_TERMINAL_INPUT;
        _ = windows.kernel32.SetConsoleMode(fd, mode);
        _ = windows.kernel32.SetConsoleOutputCP(65001);
        return winspec.WinTerm{ .mode = orig_mode, .cp = cp };
    } else {
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
}

fn reset_nonblocking_mode(fd: std.fs.File.Handle, termios: *Terminal) !void {
    if (os == .windows) {
        _ = windows.kernel32.SetConsoleOutputCP(termios.cp);
        _ = windows.kernel32.SetConsoleMode(fd, termios.mode);
    } else {
        const flags = try std.posix.fcntl(fd, std.posix.F.GETFL, 0);
        const nonblock: usize = 1 << @bitOffsetOf(std.posix.O, "NONBLOCK");
        _ = try std.posix.fcntl(fd, std.posix.F.SETFL, flags & (~nonblock));
        termios.lflag.ECHO = true;
        termios.lflag.ICANON = true;
        try std.posix.tcsetattr(fd, std.posix.TCSA.NOW, termios.*);
    }
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
    std.Thread.sleep(@intFromFloat(seconds * 1_000_000_000.0));
}

fn get_keys() void {
    const buffer = keys_buffer.items;
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
    fdin = std.fs.File.stdin().handle;

    get_console_size(std.fs.File.stdout().handle);

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
    time.set_target(@divFloor(@as(u64, 1_000_000_000), fps));
}
pub fn get_fall_frames(speed: f32) u32 {
    const fps = @divFloor(1_000_000_000, time.target);
    return @intFromFloat(@as(f32, @floatFromInt(fps)) * speed);
}

pub fn poll_keys() !void {
    keys_buffer.reset();
    keys_list.reset();

    if (os == .windows) {
        var num_events: windows.DWORD = undefined;
        _ = winspec.GetNumberOfConsoleInputEvents(fdin, &num_events);

        if (num_events > 0) {
            var input_buffer: [64]winspec.INPUT_RECORD = undefined;
            _ = winspec.ReadConsoleInputA(fdin, &input_buffer, input_buffer.len, &num_events);
            for (input_buffer) |record| {
                if (record.EventType == winspec.KEY_EVENT) {
                    const event: winspec.KEY_EVENT_RECORD = record.event.KeyEvent;
                    if (event.bKeyDown == windows.TRUE) {
                        keys_buffer.add(event.char.AsciiChar);
                    }
                }
            }
            get_keys();
        }
    } else {
        const read = std.posix.read(fdin, &keys_buffer.items) catch |err| blk: {
            if (err == std.posix.ReadError.WouldBlock) {
                break :blk 0;
            } else {
                return err;
            }
        };
        if (read > 0) {
            get_keys();
        }
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

    const wait = time.target -| elapsed;
    time.wait_time(wait);

    time.last_time = try time.get_time();
}
