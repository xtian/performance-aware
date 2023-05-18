const std = @import("std");

const Mode = enum(u2) { memory, memory_8bit_displacement, memory_16bit_displacement, register };

const RegisterMove = packed struct(u16) {
    word: bool,
    dest: bool,
    _operation: u6,
    rm: u3,
    reg: u3,
    mode: Mode,
};

const ImmediateToRegisterMove = packed struct(u8) {
    reg: u3,
    word: bool,
    _operation: u4,
};

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();

    const filename = args.next() orelse return std.debug.print("usage: sim8086 [file]\n", .{});
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const reader = file.reader();
    const writer = std.io.getStdOut().writer();

    try writer.print("; {s}\n\n", .{filename});
    try writer.print("bits 16\n\n", .{});

    while (reader.readIntNative(u8)) |byte| {
        _ = try writer.write("mov ");

        if (byte & 0b11110000 == 0b10110000) {
            const instruction = @bitCast(ImmediateToRegisterMove, byte);

            const data = if (instruction.word)
                try reader.readIntNative(u16)
            else
                try reader.readIntNative(u8);

            try writeRegister(writer, instruction.reg, instruction.word);
            try writer.print(", {}", .{data});
        } else {
            const instruction = @bitCast(RegisterMove, [_]u8{ byte, try reader.readIntNative(u8) });

            const displacement = switch (instruction.mode) {
                .memory => if (instruction.rm == 0b110) try reader.readIntNative(u16) else 0,
                .memory_8bit_displacement => try reader.readIntNative(u8),
                .memory_16bit_displacement => try reader.readIntNative(u16),
                .register => 0,
            };

            if (instruction.mode == .register) {
                try writeRegister(writer, instruction.rm, instruction.word);
                _ = try writer.write(", ");

                try writeRegister(writer, instruction.reg, instruction.word);
            } else {
                if (instruction.dest) {
                    try writeRegister(writer, instruction.reg, instruction.word);
                    _ = try writer.write(", ");
                    try writeAddressCalculation(writer, instruction.rm, instruction.mode, displacement);
                } else {
                    try writeAddressCalculation(writer, instruction.rm, instruction.mode, displacement);
                    _ = try writer.write(", ");
                    try writeRegister(writer, instruction.reg, instruction.word);
                }
            }
        }

        _ = try writer.write("\n");
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => std.debug.print("Error reading instruction: {}\n", .{err}),
    }
}

fn writeRegister(writer: anytype, register: u3, w: bool) !void {
    if (w) {
        _ = try writer.write(switch (register) {
            0b000 => "a",
            0b001 => "c",
            0b010 => "d",
            0b011 => "b",
            0b100 => "s",
            0b101 => "b",
            0b110 => "s",
            0b111 => "d",
        });

        _ = try writer.write(switch (register) {
            0b000, 0b001, 0b010, 0b011 => "x",
            0b100, 0b101 => "p",
            0b110, 0b111 => "i",
        });
    } else {
        _ = try writer.write(switch (register) {
            0b000, 0b100 => "a",
            0b001, 0b101 => "c",
            0b010, 0b110 => "d",
            0b011, 0b111 => "b",
        });

        _ = try writer.write(if (register < 0b100) "l" else "h");
    }
}

fn writeAddressCalculation(writer: anytype, rm: u3, mode: Mode, displacement: u16) !void {
    _ = try writer.write("[");
    switch (rm) {
        0b000, 0b001 => {
            _ = try writer.write("bx + ");
            _ = try writer.write(if (rm == 0b000) "si" else "di");
        },
        0b010, 0b011 => {
            _ = try writer.write("bp + ");
            _ = try writer.write(if (rm == 0b010) "si" else "di");
        },
        0b100 => _ = try writer.write("si"),
        0b101 => _ = try writer.write("di"),
        0b110 => _ = try writer.write("bp"),
        0b111 => _ = try writer.write("bx"),
    }

    if (displacement > 0) switch (mode) {
        .memory_8bit_displacement, .memory_16bit_displacement => {
            _ = try writer.print(" + {}", .{displacement});
        },
        else => unreachable,
    };
    _ = try writer.write("]");
}
