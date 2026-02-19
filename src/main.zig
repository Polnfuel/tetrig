const std = @import("std");
const tetr = @import("tetr");

const Game = tetr.Game;

pub fn main() !void {
    try tetr.init_terminal();
    defer tetr.deinit_terminal();
    errdefer tetr.deinit_terminal();

    var game = try Game.init(0, 0, 10, 20);
    defer game.deinit();
    errdefer game.deinit();

    tetr.set_target_fps(30);

    const fall_speed = 0.4;
    const fall_frames = tetr.get_fall_frames(fall_speed);
    var frame_count: u32 = 0;

    var game_running = true;

    try tetr.start_loop();
    game_loop: while (game_running) {
        const pressed_keys = try tetr.get_pressed_keys();

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
        try tetr.end_frame();
    }
}
