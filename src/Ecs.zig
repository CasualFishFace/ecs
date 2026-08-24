const std = @import("std");
const Allocator = std.mem.Allocator;

const pool = @import("pool.zig");
const Pool = pool.Pool;

allocator: Allocator,
entities: Entity,
time: Time,
io: std.Io.Threaded,
pools: std.StringHashMapUnmanaged(*pool.Erased),
systems: std.ArrayList(*const fn (*Self) anyerror!void),
deinitializers: std.ArrayList(*const fn (*Self) void),

const Self = @This();
pub const Entity = u32;

pub const Time = struct {
    delta: std.Io.Duration,
    curr: std.Io.Timestamp,
};

const empty: Self = .{
    .allocator = .failing,
    .entities = 0,
    .time = .{ .delta = .zero, .curr = .zero },
    .io = .init_single_threaded,
    .pools = .empty,
    .systems = .empty,
    .deinitializers = .empty,
};

pub fn init(gpa: Allocator) Self {
    var res = Self.empty;
    res.allocator = gpa;
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

pub fn addEntity(self: *Self, components: anytype) !Entity {
    if (!@typeInfo(@TypeOf(components)).@"struct".is_tuple)
        @compileError("expected a tuple of components");

    const entity = self.entities;
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

    self.entities += 1;
    return entity;
}

fn addDeinitializer(self: *Self, comptime C: type) !void {
    const name = @typeName(C);
    const gen = struct {
        fn deinit(ecs: *Self) void {
            for (ecs.pools.get(name).?.downcast(C).set.dense.items(.item)) |*item| {
                item.deinit(ecs.allocator);
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
                else => @compileError("expected a struct or a pointer to a struct. got `" ++
                    @typeName(T) ++ "`"),
            };
        }

        /// `partial` is a partial application of the system passed into `addSystem`.
        /// It programmatically iterates through the parameters of the system, and
        /// reifies them into a tuple used in the function call. Most of the code is
        /// executed at comptime, leaving only a for loop.
        fn partial(ecs: *Self) !void {
            comptime var arg_types: [system_info.params.len]type = undefined;
            inline for (system_info.params, 0..) |param, i| arg_types[i] = param.type.?;
            loop: for (0..ecs.entities + 1) |entity| {
                var args: @Tuple(&arg_types) = undefined;
                const arg_fields = @typeInfo(@Tuple(&arg_types)).@"struct".fields;
                inline for (system_info.params, arg_fields) |param, field| {
                    const T = UnderlyingType(param.type.?);
                    if (T == Self) {
                        if (param.type.? != *Self)
                            @compileError("getting `Ecs` information must be done through a pointer");

                        @field(args, field.name) = ecs;
                    } else {
                        const erased = ecs.pools.get(@typeName(T)) orelse break :loop;
                        const p = erased.downcast(T);

                        // entity must have ALL components to be iterated over
                        if (entity >= p.set.sparse.items.len) continue :loop;
                        const didx = p.set.sparse.items[entity] orelse continue :loop;

                        // give the field a pointer or a copy depending on the parameter of the system
                        @field(args, field.name) = switch (@typeInfo(param.type.?)) {
                            .pointer => |v| if (v.size == .one) &p.set.dense.items(.item)[didx],
                            .@"struct", .@"enum", .@"union" => p.set.dense.items(.item)[didx],
                            else => @compileError("expected a pointer to a type or a struct, union, or enum. got `" ++
                                @typeName(param.type.?) ++ "`"),
                        };
                    }
                }

                try @call(.auto, system, args);
            }
        }
    };

    try self.systems.append(self.allocator, gen.partial);
}
