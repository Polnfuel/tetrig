const std = @import("std");
const termenv = @import("termenv");
const Game = @import("game").Game;

fn starting_screen() !bool {
    _ = try termenv.stdout.write("\x1b[H\x1b[J");
    const center_x = termenv.win_width / 2;
    const center_y = termenv.win_heigth / 2;
    try termenv.stdout.print("\x1b[1m\x1b[{};{}HTETRIG\x1b[0m", .{ center_y - 5, center_x - 3 });
    try termenv.stdout.print("\x1b[{};{}HSPACE to play\x1b[{};{}HQ to quit", .{ center_y + 1, center_x - 7, center_y + 3, center_x - 3 });
    try termenv.stdout.flush();

    while (true) {
        const keys = try termenv.get_pressed_keys();
        for (keys) |key| {
            switch (key) {
                .Space => {
                    return true;
                },
                .Q => {
                    return false;
                },
                else => {},
            }
        }

        termenv.sleeptime(0.5);
    }
}

fn finishing_screen(score: u32) !void {
    _ = try termenv.stdout.write("\x1b[H\x1b[J");
    const center_x = termenv.win_width / 2;
    const center_y = termenv.win_heigth / 2;
    try termenv.stdout.print("\x1b[1m\x1b[{};{}HGAME OVER\x1b[0m", .{ center_y - 2, center_x - 4 });
    try termenv.stdout.print("\x1b[{};{}HScore: {d:>6}", .{ center_y + 1, center_x - 6, score });
    try termenv.stdout.print("\x1b[{};1H\n", .{termenv.win_heigth - 1});
    try termenv.stdout.flush();
}

fn check_proper_terminal_size(w: u32, h: u32) bool {
    if (termenv.win_width >= 2 * (w + 7) and termenv.win_heigth >= h + 2) {
        return true;
    }
    return false;
}

const Origin = struct {
    x: u32,
    y: u32,
};

fn centered_board_coords(w: u32, h: u32) Origin {
    const x = (termenv.win_width / 2 - (w + 7)) / 2;
    const y = (termenv.win_heigth - h) / 2;
    return Origin{ .x = x, .y = y };
}

pub fn main() !void {
    try termenv.init_terminal();
    defer termenv.deinit_terminal();
    errdefer termenv.deinit_terminal();

    const proper_size = check_proper_terminal_size(10, 20);
    if (!proper_size) {
        _ = try termenv.stdout.write("\x1b[H\x1b[JYout terminal window is\ntoo small for this game\n");
        return;
    }

    const continued = try starting_screen();
    if (!continued) {
        _ = try termenv.stdout.write("\x1b[H\x1b[J");
        return;
    }

    const origin = centered_board_coords(10, 20);

    var game = try Game.init(origin.x, origin.y, 10, 20);
    defer game.deinit();
    errdefer game.deinit();

    termenv.set_target_fps(30);

    const fall_speed = 0.4;
    const fall_frames = termenv.get_fall_frames(fall_speed);
    var frame_count: u32 = 0;

    var game_running = true;

    try termenv.start_loop();
    game_loop: while (game_running) {
        const pressed_keys = try termenv.get_pressed_keys();

        for (pressed_keys) |key| {
            switch (key) {
                .Q => {
                    game_running = false;
                },
                .Left => {
                    game_running = game.move_left();
                },
                .Right => {
                    game_running = game.move_right();
                },
                .Down => {
                    game_running = game.place_down();
                },
                .Up => {
                    game_running = game.rotate_figure();
                },
                else => {},
            }
            if (game_running == false) {
                break :game_loop;
            }
        }

        if (frame_count % fall_frames == 0) {
            if (game.move_down() == false) {
                break :game_loop;
            }
        }

        try game.draw();

        frame_count += 1;
        try termenv.end_frame();
    }

    try finishing_screen(game.score);
}
