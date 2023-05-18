const std = @import("std");

const Operation = enum(u6) { mov = 0b100010 };
const Mode = enum(u2) { register = 0b11 };

const Instruction = packed struct(u16) {
    w: bool,
    d: bool,
    operation: Operation,
    operand: u3,
    register: u3,
    mode: Mode,
};

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();

    const filename = args.next().?;
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const reader = file.reader();

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const writer = bw.writer();

    try writer.print("; {s}\n\n", .{filename});
    try writer.print("bits 16\n\n", .{});

    while (reader.readStruct(Instruction)) |instruction| {
        _ = try writer.write(switch (instruction.operation) {
            .mov => "mov",
        });

        _ = try writer.write(" ");
        try writeAddress("operand", writer, instruction);
        try writer.print(", ", .{});
        try writeAddress("register", writer, instruction);
        try writer.print("\n", .{});
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => std.debug.print("Error reading instruction: {}\n", .{err}),
    }

    try bw.flush();
}

fn writeAddress(
    comptime field: []const u8,
    writer: anytype,
    instruction: Instruction,
) !void {
    if (instruction.w) {
        _ = try writer.write(switch (@field(instruction, field)) {
            0b000 => "a",
            0b001 => "c",
            0b010 => "d",
            0b011 => "b",
            0b100 => "s",
            0b101 => "b",
            0b110 => "s",
            0b111 => "d",
        });

        _ = try writer.write(switch (@field(instruction, field)) {
            0b000, 0b001, 0b010, 0b011 => "x",
            0b100, 0b101 => "p",
            0b110, 0b111 => "i",
        });
    } else {
        _ = try writer.write(switch (@field(instruction, field)) {
            0b000, 0b100 => "a",
            0b001, 0b101 => "c",
            0b010, 0b110 => "d",
            0b011, 0b111 => "b",
        });

        _ = try writer.write(if (instruction.operand < 0b100) "l" else "h");
    }
}
