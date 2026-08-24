This is HEAVILY inspired by the [Bevy](https://bevy.org/) game engine. But using Zig's comptime, I
am able to entirely get rid of the `Query` type that is used in Bevy. The code is quite messy, as
of right now, but I will be documenting it all and refactoring as needed.

This code snippet is subject to change, but as of right now, usage of my ECS looks like this:
```zig
const std = @import("std");
const Ecs = @import("Ecs.zig");

pub fn main(init: std.process.Init) !void {
    var ecs = Ecs.empty;
    ecs.allocator = init.gpa;

    _ = try ecs.addEntity(.{
        Chud.maxChildren(3),
    });

    try ecs.addSystems(.{
        chudSpawner,
        chudling,
    });

    for (0..4) |_| try ecs.step();

    defer ecs.deinit();
}

pub const Chud = struct {
    children: std.ArrayList(Ecs.Entity),
    max_children: ?Ecs.Entity,

    pub fn maxChildren(max_children: ?Ecs.Entity) @This() {
        return .{
            .children = .empty,
            .max_children = max_children,
        };
    }

    pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        self.children.deinit(gpa);
        self.* = undefined;
    }
};

pub const Chudling = struct {};

pub fn chudSpawner(ecs: *Ecs, chud: *Chud) !void {
    if (chud.max_children == null or chud.children.items.len < chud.max_children.?) {
        const child = try ecs.addEntity(.{Chudling{}});
        try chud.children.append(ecs.allocator, child);
    }

    switch (chud.children.items.len) {
        0 => std.debug.print("I am a chud with no chudlings :(\n", .{}),
        1 => std.debug.print("I am a chud and I have 1 chudling :D\n", .{}),
        else => std.debug.print("I am a chud and I have {} chudlings :D\n", .{
            chud.children.items.len,
        }),
    }
}

pub fn chudling(_: Chudling) !void {
    std.debug.print("I am a chudling :D\n", .{});
}
```

Output:
```
I am a chud and I have 1 chudling :D
I am a chudling :D
I am a chud and I have 2 chudlings :D
I am a chudling :D
I am a chudling :D
I am a chud and I have 3 chudlings :D
I am a chudling :D
I am a chudling :D
I am a chudling :D
I am a chud and I have 3 chudlings :D
I am a chudling :D
I am a chudling :D
I am a chudling :D
```
