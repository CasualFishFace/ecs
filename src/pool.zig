const std = @import("std");
const Allocator = std.mem.Allocator;

const Ecs = @import("Ecs.zig");
const sparse_set = @import("sparse_set.zig");
const SparseSet = sparse_set.SparseSet;

pub fn Pool(comptime T: type) type {
    return struct {
        set: SparseSet(Ecs.Entity, T),
        erased: Erased,

        const Self = @This();

        pub const empty = Self{
            .set = .empty,
            .erased = .impl(Self),
        };

        pub fn deinit(self: *Self, gpa: Allocator) void {
            self.set.deinit(gpa);
            self.* = undefined;
        }

        pub fn destroy(self: *Self, gpa: Allocator) void {
            self.deinit(gpa);
            gpa.destroy(self);
        }

        pub fn putNoClobber(
            self: *Self,
            gpa: Allocator,
            entity: Ecs.Entity,
            component: T,
        ) !void {
            return self.set.putNoClobber(gpa, entity, component);
        }

        pub fn put(
            self: *Self,
            gpa: Allocator,
            entity: Ecs.Entity,
            component: T,
        ) !void {
            return self.set.put(gpa, entity, component);
        }

        pub fn remove(self: *Self, entity: Ecs.Entity) bool {
            return if (self.set.remove(entity)) |_| true else false;
        }
    };
}

pub const Erased = struct {
    vtable: *const VTable,

    const VTable = struct {
        deinit: *const fn (*Erased, Allocator) void,
        destroy: *const fn (*Erased, Allocator) void,
    };

    pub fn impl(comptime P: type) Erased {
        const gen = struct {
            fn deinit(erased: *Erased, gpa: Allocator) void {
                const self: *P = @fieldParentPtr("erased", erased);
                self.deinit(gpa);
            }

            fn destroy(erased: *Erased, gpa: Allocator) void {
                const self: *P = @fieldParentPtr("erased", erased);
                self.destroy(gpa);
            }
        };

        return .{ .vtable = &.{
            .deinit = gen.deinit,
            .destroy = gen.destroy,
        } };
    }

    pub fn deinit(erased: *Erased, gpa: Allocator) void {
        return erased.vtable.deinit(erased, gpa);
    }

    pub fn destroy(erased: *Erased, gpa: Allocator) void {
        return erased.vtable.destroy(erased, gpa);
    }

    pub fn downcast(erased: *Erased, comptime T: type) *Pool(T) {
        return @fieldParentPtr("erased", erased);
    }

    pub fn downcastConst(erased: *const Erased, comptime T: type) *const Pool(T) {
        return @fieldParentPtr("erased", erased);
    }

    pub fn putNoClobber(
        erased: *Erased,
        gpa: Allocator,
        entity: Ecs.Entity,
        component: anytype,
    ) !void {
        return erased.vtable.putNoClobber(erased, gpa, entity, component);
    }

    pub fn put(
        erased: *Erased,
        comptime T: type,
        gpa: Allocator,
        entity: Ecs.Entity,
        component: T,
    ) !void {
        return erased.vtable.put(erased, gpa, entity, component);
    }

    pub fn remove(erased: *Erased, entity: Ecs.Entity) !void {
        return erased.vtable.remove(erased, entity);
    }
};
