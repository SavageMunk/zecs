const std = @import("std");
const Allocator = std.mem.Allocator;
const Component = @import("../core/component.zig").Component;
const ComponentHelper = @import("../core/component.zig").ComponentHelper;

/// 2D Position component
pub const Position = struct {
    const Self = @This();
    
    component: Component,
    x: f32,
    y: f32,
    
    pub fn init(x: f32, y: f32, allocator: Allocator) !*Self {
        return ComponentHelper(Self).init(.{
            .component = undefined,
            .x = x,
            .y = y,
        }, allocator);
    }
    
    pub fn fromComponent(component: *Component) *Self {
        return ComponentHelper(Self).fromComponent(component);
    }
    
    pub fn set(self: *Self, x: f32, y: f32) void {
        self.x = x;
        self.y = y;
    }
    
    pub fn translate(self: *Self, dx: f32, dy: f32) void {
        self.x += dx;
        self.y += dy;
    }
    
    pub fn distanceTo(self: *Self, other: *Self) f32 {
        const dx = self.x - other.x;
        const dy = self.y - other.y;
        return @sqrt(dx * dx + dy * dy);
    }
};

/// 2D Velocity component
pub const Velocity = struct {
    const Self = @This();
    
    component: Component,
    dx: f32,
    dy: f32,
    
    pub fn init(dx: f32, dy: f32, allocator: Allocator) !*Self {
        return ComponentHelper(Self).init(.{
            .component = undefined,
            .dx = dx,
            .dy = dy,
        }, allocator);
    }
    
    pub fn fromComponent(component: *Component) *Self {
        return ComponentHelper(Self).fromComponent(component);
    }
    
    pub fn set(self: *Self, dx: f32, dy: f32) void {
        self.dx = dx;
        self.dy = dy;
    }
    
    pub fn magnitude(self: *Self) f32 {
        return @sqrt(self.dx * self.dx + self.dy * self.dy);
    }
    
    pub fn normalize(self: *Self) void {
        const mag = self.magnitude();
        if (mag > 0) {
            self.dx /= mag;
            self.dy /= mag;
        }
    }
    
    pub fn scale(self: *Self, factor: f32) void {
        self.dx *= factor;
        self.dy *= factor;
    }
};

/// Rotation component (2D angle in radians)
pub const Rotation = struct {
    const Self = @This();
    
    component: Component,
    angle: f32,
    
    pub fn init(angle: f32, allocator: Allocator) !*Self {
        return ComponentHelper(Self).init(.{
            .component = undefined,
            .angle = angle,
        }, allocator);
    }
    
    pub fn fromComponent(component: *Component) *Self {
        return ComponentHelper(Self).fromComponent(component);
    }
    
    pub fn set(self: *Self, angle: f32) void {
        self.angle = angle;
    }
    
    pub fn rotate(self: *Self, delta_angle: f32) void {
        self.angle += delta_angle;
        // Keep angle in range [0, 2π]
        while (self.angle < 0) self.angle += 2 * std.math.pi;
        while (self.angle >= 2 * std.math.pi) self.angle -= 2 * std.math.pi;
    }
    
    pub fn toDegrees(self: *Self) f32 {
        return self.angle * 180.0 / std.math.pi;
    }
    
    pub fn fromDegrees(degrees: f32) f32 {
        return degrees * std.math.pi / 180.0;
    }
};

/// 2D Scale component
pub const Scale = struct {
    const Self = @This();
    
    component: Component,
    x: f32,
    y: f32,
    
    pub fn init(x: f32, y: f32, allocator: Allocator) !*Self {
        return ComponentHelper(Self).init(.{
            .component = undefined,
            .x = x,
            .y = y,
        }, allocator);
    }
    
    pub fn uniform(scale: f32, allocator: Allocator) !*Self {
        return Self.init(scale, scale, allocator);
    }
    
    pub fn fromComponent(component: *Component) *Self {
        return ComponentHelper(Self).fromComponent(component);
    }
    
    pub fn set(self: *Self, x: f32, y: f32) void {
        self.x = x;
        self.y = y;
    }
    
    pub fn setUniform(self: *Self, scale: f32) void {
        self.x = scale;
        self.y = scale;
    }
    
    pub fn multiply(self: *Self, factor: f32) void {
        self.x *= factor;
        self.y *= factor;
    }
};

// Helper function to get component type IDs
pub fn getPositionTypeId() u32 {
    return ComponentHelper(Position).TYPE_ID;
}

pub fn getVelocityTypeId() u32 {
    return ComponentHelper(Velocity).TYPE_ID;
}

pub fn getRotationTypeId() u32 {
    return ComponentHelper(Rotation).TYPE_ID;
}

pub fn getScaleTypeId() u32 {
    return ComponentHelper(Scale).TYPE_ID;
}

test "position component" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const pos = try Position.init(10.0, 20.0, allocator);
    defer allocator.destroy(pos);
    
    try std.testing.expectEqual(@as(f32, 10.0), pos.x);
    try std.testing.expectEqual(@as(f32, 20.0), pos.y);
    
    pos.translate(5.0, -3.0);
    try std.testing.expectEqual(@as(f32, 15.0), pos.x);
    try std.testing.expectEqual(@as(f32, 17.0), pos.y);
}

test "velocity component" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const vel = try Velocity.init(3.0, 4.0, allocator);
    defer allocator.destroy(vel);
    
    try std.testing.expectEqual(@as(f32, 5.0), vel.magnitude()); // 3-4-5 triangle
    
    vel.normalize();
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), vel.magnitude(), 0.001);
}
