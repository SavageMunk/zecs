const std = @import("std");

// Forward declaration
const World = @import("world.zig").World;

/// System definition for the ECS
pub const System = struct {
    const Self = @This();
    
    /// System name (must be unique)
    name: []const u8,
    
    /// System update function
    update: *const fn(*World, f32) anyerror!void,
    
    /// System priority (higher = runs first)
    priority: i32,
    
    /// Whether the system is enabled
    enabled: bool,
    
    /// Initialize a new system
    pub fn init(name: []const u8, update_fn: *const fn(*World, f32) anyerror!void) Self {
        return Self{
            .name = name,
            .update = update_fn,
            .priority = 0,
            .enabled = true,
        };
    }
    
    /// Initialize a system with priority
    pub fn initWithPriority(name: []const u8, update_fn: *const fn(*World, f32) anyerror!void, priority: i32) Self {
        return Self{
            .name = name,
            .update = update_fn,
            .priority = priority,
            .enabled = true,
        };
    }
    
    /// Enable or disable the system
    pub fn setEnabled(self: *Self, enabled: bool) void {
        self.enabled = enabled;
    }
    
    /// Set the system priority
    pub fn setPriority(self: *Self, priority: i32) void {
        self.priority = priority;
    }
};

/// System builder for easier system creation
pub const SystemBuilder = struct {
    const Self = @This();
    
    name: []const u8,
    update_fn: *const fn(*World, f32) anyerror!void,
    sys_priority: i32 = 0,
    sys_enabled: bool = true,
    
    pub fn init(name: []const u8, update_fn: *const fn(*World, f32) anyerror!void) Self {
        return Self{
            .name = name,
            .update_fn = update_fn,
        };
    }
    
    pub fn priority(self: Self, p: i32) Self {
        var result = self;
        result.sys_priority = p;
        return result;
    }
    
    pub fn enabled(self: Self, e: bool) Self {
        var result = self;
        result.sys_enabled = e;
        return result;
    }
    
    pub fn build(self: Self) System {
        return System{
            .name = self.name,
            .update = self.update_fn,
            .priority = self.sys_priority,
            .enabled = self.sys_enabled,
        };
    }
};

// Example system function
fn exampleSystem(world: *World, dt: f32) !void {
    _ = world;
    _ = dt;
    // System logic here
}

test "system creation" {
    const system = System.init("test_system", exampleSystem);
    try std.testing.expectEqualStrings("test_system", system.name);
    try std.testing.expectEqual(@as(i32, 0), system.priority);
    try std.testing.expect(system.enabled);
}

test "system builder" {
    const system = SystemBuilder.init("test_system", exampleSystem)
        .priority(10)
        .enabled(false)
        .build();
    
    try std.testing.expectEqualStrings("test_system", system.name);
    try std.testing.expectEqual(@as(i32, 10), system.priority);
    try std.testing.expect(!system.enabled);
}
