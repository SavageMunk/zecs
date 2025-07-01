//! Built-in systems for ZECS

// Movement and physics
pub const movementSystem = @import("movement.zig").movementSystem;
pub const velocitySystem = @import("movement.zig").velocitySystem;

// Gameplay mechanics
pub const healthSystem = @import("gameplay.zig").healthSystem;
pub const lifetimeSystem = @import("gameplay.zig").lifetimeSystem;
pub const timerSystem = @import("gameplay.zig").timerSystem;

// AI and behavior
pub const aiSystem = @import("ai.zig").aiSystem;
pub const wanderingSystem = @import("ai.zig").wanderingSystem;
