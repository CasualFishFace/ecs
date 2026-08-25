const std = @import("std");
const Allocator = std.mem.Allocator;
pub const Random = std.Random;

const pool = @import("pool.zig");
const Pool = pool.Pool;

allocator: Allocator,
entities: Entity,
removed: std.ArrayList(Entity),
time: Time,
io: std.Io.Threaded,
random: Random.DefaultPrng = .init(0),
pools: std.StringHashMapUnmanaged(*pool.Erased),
systems: std.ArrayList(*const fn (*Self) anyerror!void),
deinitializers: std.ArrayList(*const fn (*Self) void),

const Self = @This();
pub const Entity = u32;

pub const Options = struct {
    seed: u64 = 0,
};

pub const Time = struct {
    delta: std.Io.Duration,
    curr: std.Io.Timestamp,
};

const empty: Self = .{
    .allocator = .failing,
    .entities = 0,
    .removed = .empty,
    .time = .{ .delta = .zero, .curr = .zero },
    .io = .init_single_threaded,
    .pools = .empty,
    .systems = .empty,
    .deinitializers = .empty,
};

pub fn init(gpa: Allocator, opts: Options) Self {
    var res = Self.empty;
    res.allocator = gpa;
    res.random.seed(opts.seed);
    res.time = .{
        .delta = .zero,
        .curr = .now(res.io.io(), .boot),
    };

    return res;
}

pub fn deinit(self: *Self) void {
    var erased_it = self.pools.valueIterator();
    for (self.deinitializers.items) |deinitializer| deinitializer(self);
    while (erased_it.next()) |erased| erased.*.destroy(self.allocator);
    self.systems.deinit(self.allocator);
    self.pools.deinit(self.allocator);
    self.deinitializers.deinit(self.allocator);
    self.* = undefined;
}

pub fn run(self: *Self) !void {
    while (true) try self.step();
}

pub fn step(self: *Self) !void {
    for (self.systems.items) |system| {
        try system(self);
    }

    const now = std.Io.Timestamp.now(self.io.io(), .boot);
    const delta = self.time.curr.durationTo(now);
    self.time = .{
        .curr = now,
        .delta = delta,
    };
}

pub fn removeEntity(self: *Self, entity: Entity) bool {
    var it = self.pools.valueIterator();
    var existed = false;
    while (it.next()) |erased| {
        existed = erased.*.remove(entity) or existed;
    }

    if (existed) self.removed.append(self.allocator, entity) catch unreachable;
    return existed;
}

pub fn addEntity(self: *Self, components: anytype) !Entity {
    if (!@typeInfo(@TypeOf(components)).@"struct".is_tuple)
        @compileError("expected a tuple of components");

    const removedEntities = self.removed.items.len > 0;
    const entity = self.removed.getLastOrNull() orelse self.entities;
    inline for (components) |component| {
        const C = @TypeOf(component);
        const name = @typeName(C);
        const erased = try self.pools.getOrPut(self.allocator, name);
        if (!erased.found_existing) {
            const p = try self.allocator.create(Pool(C));
            if (@hasDecl(C, "deinit")) try self.addDeinitializer(C);
            p.* = .empty;
            erased.value_ptr.* = &p.erased;
        }

        const p = erased.value_ptr.*.downcast(C);
        try p.put(self.allocator, entity, component);
    }

    switch (removedEntities) {
        false => self.entities += 1,
        true => _ = self.removed.pop(),
    }

    return entity;
}

fn addDeinitializer(self: *Self, comptime C: type) !void {
    const name = @typeName(C);
    const gen = struct {
        fn deinit(ecs: *Self) void {
            for (ecs.pools.get(name).?.downcast(C).set.dense.items) |*item| {
                item.deinit(ecs);
            }
        }
    };

    try self.deinitializers.append(self.allocator, gen.deinit);
}

/// Add a group of functions called `systems` to the ECS. These will be run
/// every tick.
pub fn addSystems(self: *Self, systems: anytype) !void {
    if (!@typeInfo(@TypeOf(systems)).@"struct".is_tuple)
        @compileError("expected a tuple of functions");

    inline for (systems) |system| try self.addSystem(system);
}

fn addSystem(self: *Self, system: anytype) !void {
    const S = @TypeOf(system);
    const system_info = @typeInfo(S).@"fn";
    const gen = struct {
        fn UnderlyingType(comptime T: type) type {
            return switch (@typeInfo(T)) {
                .@"struct", .@"enum", .@"union" => T,
                .pointer => |v| if (v.size == .one)
                    v.child
                else
                    @compileError("expected a pointer to a single `" ++ @typeName(v.child) ++ "`"),
                .int => if (T == Entity) T else @compileError("expected the type to be `Entity`"),
                else => @compileError("expected a struct or a pointer to a struct. got `" ++
                    @typeName(T) ++ "`"),
            };
        }

        inline fn assembleArgs(
            comptime arg_types: []const type,
            ecs: *Self,
            ent: Entity,
        ) error{NoPool}!?@Tuple(arg_types) {
            var args: @Tuple(arg_types) = undefined;
            const arg_fields = @typeInfo(@Tuple(arg_types)).@"struct".fields;
            inline for (system_info.params, arg_fields) |param, field| {
                const T = UnderlyingType(param.type.?);
                switch (T) {
                    Entity => @field(args, field.name) = ent,
                    Self => {
                        if (param.type.? != *Self)
                            @compileError("getting `Ecs` information must be done through a pointer");

                        @field(args, field.name) = ecs;
                    },
                    Random => {
                        if (param.type.? != Random)
                            @compileError("using randomness must be done with `Random`, not `*Random`");

                        @field(args, field.name) = ecs.random.random();
                    },
                    else => {
                        const expected_ptr_struct_enum_union =
                            "expected a pointer or a struct, union, or enum. got `" ++
                            @typeName(param.type.?) ++ "`";

                        const erased = ecs.pools.get(@typeName(T)) orelse
                            return error.NoPool;

                        const p = erased.downcast(T);
                        @field(args, field.name) = switch (@typeInfo(param.type.?)) {
                            .pointer => |v| if (v.size == .one)
                                p.set.getPtr(ent) orelse return null
                            else
                                @compileError(expected_ptr_struct_enum_union),
                            .@"struct", .@"enum", .@"union" => p.set.get(ent) orelse return null,
                            else => @compileError(expected_ptr_struct_enum_union),
                        };
                    },
                }
            }

            return args;
        }

        /// `partial` is a partial application of the system passed into `addSystem`.
        /// It programmatically iterates through the parameters of the system, and
        /// reifies them into a tuple used in the function call. Most of the code is
        /// executed at comptime, leaving only a for loop.
        fn partial(ecs: *Self) !void {
            comptime var arg_types: [system_info.params.len]type = undefined;
            inline for (system_info.params, 0..) |param, i| arg_types[i] = param.type.?;
            for (0..ecs.entities + 1) |entity| {
                const args = assembleArgs(&arg_types, ecs, @truncate(entity)) catch {
                    break;
                } orelse continue;

                try @call(.auto, system, args);
            }
        }
    };

    try self.systems.append(self.allocator, gen.partial);
}
