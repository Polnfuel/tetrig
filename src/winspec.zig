const std = @import("std");
const windows = std.os.windows;

pub const ENABLE_ECHO_INPUT: windows.DWORD = 0x0004;
pub const ENABLE_LINE_INPUT: windows.DWORD = 0x0002;
pub const ENABLE_VIRTUAL_TERMINAL_INPUT: windows.DWORD = 0x0200;

pub const WinTerm = struct {
    mode: windows.DWORD,
    cp: windows.UINT,
};

pub const KEY_EVENT: windows.WORD = 0x0001;

pub const KEY_EVENT_RECORD = extern struct {
    bKeyDown: windows.BOOL,
    wRepeatCount: windows.WORD,
    wVirtualKeyCode: windows.WORD,
    wVirtualScanCode: windows.WORD,
    char: extern union {
        UnicodeChar: windows.WCHAR,
        AsciiChar: windows.CHAR,
    },
    dwControlKeyState: windows.DWORD,
};

const MOUSE_EVENT_RECORD = extern struct {
    dwMousePosition: windows.COORD,
    dwButtonState: windows.DWORD,
    dwControlKeyState: windows.DWORD,
    dwEventFlags: windows.DWORD,
};

const WINDOW_BUFFER_SIZE_RECORD = extern struct {
    dwSize: windows.COORD,
};

const MENU_EVENT_RECORD = extern struct {
    dwCommandId: windows.UINT,
};

const FOCUS_EVENT_RECORD = extern struct {
    bSetFocus: windows.BOOL,
};

pub const INPUT_RECORD = extern struct {
    EventType: windows.WORD,
    event: extern union {
        KeyEvent: KEY_EVENT_RECORD,
        MouseEvent: MOUSE_EVENT_RECORD,
        WindowBufferSizeEvent: WINDOW_BUFFER_SIZE_RECORD,
        MenuEvent: MENU_EVENT_RECORD,
        FocusEvent: FOCUS_EVENT_RECORD,
    },
};

pub extern "kernel32" fn ReadConsoleInputA(
    hConsoleInput: windows.HANDLE,
    lpBuffer: [*]INPUT_RECORD,
    nLength: windows.DWORD,
    lpNumberOfEventsRead: *windows.DWORD,
) callconv(.winapi) windows.BOOL;

pub extern "kernel32" fn GetNumberOfConsoleInputEvents(
    hConsoleInput: windows.HANDLE,
    lpcNumberOfEvents: *windows.DWORD,
) callconv(.winapi) windows.BOOL;
