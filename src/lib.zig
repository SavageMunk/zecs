//! ZECS - Zig Entity Component System Library
//! A high-performance ECS framework for simulations and games

const std = @import("std");

// Core ECS types
pub const EntityId = @import("core/entity.zig").EntityId;
pub const World = @import("core/world.zig").World;
pub const SqliteWorld = @import("core/sqlite_world.zig").SqliteWorld;
pub const Component = @import("core/component.zig").Component;
pub const System = @import("core/system.zig").System;
pub const Query = @import("core/query.zig").Query;

// Component helpers
pub const ComponentHelper = @import("core/component.zig").ComponentHelper;

// Built-in components
pub const components = @import("components/mod.zig");

// Built-in systems 
pub const systems = @import("systems/mod.zig");

// Utilities
pub const utils = @import("utils/mod.zig");

// Constants
pub const INVALID_ENTITY = @import("core/entity.zig").INVALID_ENTITY;

// Re-export commonly used types
pub const Position = components.Position;
pub const Velocity = components.Velocity;
pub const Health = components.Health;
pub const AI = components.AI;

// Re-export commonly used systems
pub const movementSystem = systems.movementSystem;
pub const healthSystem = systems.healthSystem;
pub const aiSystem = systems.aiSystem;

// Tests
test {
    std.testing.refAllDecls(@This());
}
