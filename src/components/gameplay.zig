const std = @import("std");
const Allocator = std.mem.Allocator;
const Component = @import("../core/component.zig").Component;
const ComponentHelper = @import("../core/component.zig").ComponentHelper;
const EntityId = @import("../core/entity.zig").EntityId;

/// Health component for entities that can take damage
pub const Health = struct {
    const Self = @This();
    
    component: Component,
    current: i32,
    max: i32,
    regeneration: f32, // HP per second
    
    pub fn init(max_health: i32, allocator: Allocator) !*Self {
        return ComponentHelper(Self).init(.{
            .component = undefined,
            .current = max_health,
            .max = max_health,
            .regeneration = 0.0,
        }, allocator);
    }
    
    pub fn initWithRegen(max_health: i32, regen_rate: f32, allocator: Allocator) !*Self {
        return ComponentHelper(Self).init(.{
            .component = undefined,
            .current = max_health,
            .max = max_health,
            .regeneration = regen_rate,
        }, allocator);
    }
    
    pub fn fromComponent(component: *Component) *Self {
        return ComponentHelper(Self).fromComponent(component);
    }
    
    pub fn takeDamage(self: *Self, damage: i32) void {
        self.current = @max(0, self.current - damage);
    }
    
    pub fn heal(self: *Self, amount: i32) void {
        self.current = @min(self.max, self.current + amount);
    }
    
    pub fn isAlive(self: *Self) bool {
        return self.current > 0;
    }
    
    pub fn isDead(self: *Self) bool {
        return self.current <= 0;
    }
    
    pub fn getHealthPercent(self: *Self) f32 {
        if (self.max <= 0) return 0.0;
        return @as(f32, @floatFromInt(self.current)) / @as(f32, @floatFromInt(self.max));
    }
    
    pub fn regenerate(self: *Self, dt: f32) void {
        if (self.regeneration > 0 and self.current < self.max) {
            const regen_amount = @as(i32, @intFromFloat(self.regeneration * dt));
            self.heal(regen_amount);
        }
    }
};

/// Energy/Mana component for abilities and actions
pub const Energy = struct {
    const Self = @This();
    
    component: Component,
    current: f32,
    max: f32,
    regeneration: f32, // Energy per second
    
    pub fn init(max_energy: f32, allocator: Allocator) !*Self {
        return ComponentHelper(Self).init(.{
            .component = undefined,
            .current = max_energy,
            .max = max_energy,
            .regeneration = 0.0,
        }, allocator);
    }
    
    pub fn initWithRegen(max_energy: f32, regen_rate: f32, allocator: Allocator) !*Self {
        return ComponentHelper(Self).init(.{
            .component = undefined,
            .current = max_energy,
            .max = max_energy,
            .regeneration = regen_rate,
        }, allocator);
    }
    
    pub fn fromComponent(component: *Component) *Self {
        return ComponentHelper(Self).fromComponent(component);
    }
    
    pub fn consume(self: *Self, amount: f32) bool {
        if (self.current >= amount) {
            self.current -= amount;
            return true;
        }
        return false;
    }
    
    pub fn restore(self: *Self, amount: f32) void {
        self.current = @min(self.max, self.current + amount);
    }
    
    pub fn getEnergyPercent(self: *Self) f32 {
        if (self.max <= 0) return 0.0;
        return self.current / self.max;
    }
    
    pub fn regenerate(self: *Self, dt: f32) void {
        if (self.regeneration > 0 and self.current < self.max) {
            self.restore(self.regeneration * dt);
        }
    }
};

/// AI State for basic AI behavior
pub const AIState = enum {
    idle,
    wandering,
    chasing,
    fleeing,
    attacking,
    dead,
};

/// Basic AI component
pub const AI = struct {
    const Self = @This();
    
    component: Component,
    state: AIState,
    target: ?EntityId,
    state_timer: f32, // How long in current state
    decision_cooldown: f32, // Time until next decision
    
    pub fn init(initial_state: AIState, allocator: Allocator) !*Self {
        return ComponentHelper(Self).init(.{
            .component = undefined,
            .state = initial_state,
            .target = null,
            .state_timer = 0.0,
            .decision_cooldown = 0.0,
        }, allocator);
    }
    
    pub fn fromComponent(component: *Component) *Self {
        return ComponentHelper(Self).fromComponent(component);
    }
    
    pub fn setState(self: *Self, new_state: AIState) void {
        if (self.state != new_state) {
            self.state = new_state;
            self.state_timer = 0.0;
        }
    }
    
    pub fn setTarget(self: *Self, target: ?EntityId) void {
        self.target = target;
    }
    
    pub fn update(self: *Self, dt: f32) void {
        self.state_timer += dt;
        if (self.decision_cooldown > 0) {
            self.decision_cooldown -= dt;
        }
    }
    
    pub fn canMakeDecision(self: *Self) bool {
        return self.decision_cooldown <= 0;
    }
    
    pub fn setDecisionCooldown(self: *Self, cooldown: f32) void {
        self.decision_cooldown = cooldown;
    }
};

/// Lifetime component - entity dies after time expires
pub const Lifetime = struct {
    const Self = @This();
    
    component: Component,
    remaining: f32,
    
    pub fn init(lifetime_seconds: f32, allocator: Allocator) !*Self {
        return ComponentHelper(Self).init(.{
            .component = undefined,
            .remaining = lifetime_seconds,
        }, allocator);
    }
    
    pub fn fromComponent(component: *Component) *Self {
        return ComponentHelper(Self).fromComponent(component);
    }
    
    pub fn update(self: *Self, dt: f32) void {
        self.remaining -= dt;
    }
    
    pub fn isExpired(self: *Self) bool {
        return self.remaining <= 0;
    }
    
    pub fn getTimeLeft(self: *Self) f32 {
        return @max(0, self.remaining);
    }
    
    pub fn getPercentLeft(self: *Self, original_lifetime: f32) f32 {
        if (original_lifetime <= 0) return 0.0;
        return @max(0, self.remaining / original_lifetime);
    }
};

/// Timer component for recurring events
pub const Timer = struct {
    const Self = @This();
    
    component: Component,
    duration: f32,
    elapsed: f32,
    repeat: bool,
    active: bool,
    
    pub fn init(duration: f32, repeat: bool, allocator: Allocator) !*Self {
        return ComponentHelper(Self).init(.{
            .component = undefined,
            .duration = duration,
            .elapsed = 0.0,
            .repeat = repeat,
            .active = true,
        }, allocator);
    }
    
    pub fn fromComponent(component: *Component) *Self {
        return ComponentHelper(Self).fromComponent(component);
    }
    
    pub fn update(self: *Self, dt: f32) bool {
        if (!self.active) return false;
        
        self.elapsed += dt;
        
        if (self.elapsed >= self.duration) {
            if (self.repeat) {
                self.elapsed = 0.0;
            } else {
                self.active = false;
            }
            return true; // Timer triggered
        }
        
        return false;
    }
    
    pub fn reset(self: *Self) void {
        self.elapsed = 0.0;
        self.active = true;
    }
    
    pub fn getProgress(self: *Self) f32 {
        if (self.duration <= 0) return 1.0;
        return @min(1.0, self.elapsed / self.duration);
    }
};

// Helper functions to get component type IDs
pub fn getHealthTypeId() u32 {
    return ComponentHelper(Health).TYPE_ID;
}

pub fn getEnergyTypeId() u32 {
    return ComponentHelper(Energy).TYPE_ID;
}

pub fn getAITypeId() u32 {
    return ComponentHelper(AI).TYPE_ID;
}

pub fn getLifetimeTypeId() u32 {
    return ComponentHelper(Lifetime).TYPE_ID;
}

pub fn getTimerTypeId() u32 {
    return ComponentHelper(Timer).TYPE_ID;
}

test "health component" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const health = try Health.init(100, allocator);
    defer allocator.destroy(health);
    
    try std.testing.expect(health.isAlive());
    try std.testing.expectEqual(@as(f32, 1.0), health.getHealthPercent());
    
    health.takeDamage(25);
    try std.testing.expectEqual(@as(i32, 75), health.current);
    try std.testing.expectEqual(@as(f32, 0.75), health.getHealthPercent());
    
    health.heal(10);
    try std.testing.expectEqual(@as(i32, 85), health.current);
    
    health.takeDamage(200); // Overkill
    try std.testing.expect(health.isDead());
    try std.testing.expectEqual(@as(i32, 0), health.current);
}

test "timer component" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const timer = try Timer.init(1.0, false, allocator);
    defer allocator.destroy(timer);
    
    try std.testing.expect(!timer.update(0.5)); // Not triggered yet
    try std.testing.expectEqual(@as(f32, 0.5), timer.getProgress());
    
    try std.testing.expect(timer.update(0.6)); // Triggered (total 1.1 > 1.0)
    try std.testing.expect(!timer.active); // One-shot timer is now inactive
}
