//! Built-in components for ZECS

// Core spatial components
pub const Position = @import("spatial.zig").Position;
pub const Velocity = @import("spatial.zig").Velocity;
pub const Rotation = @import("spatial.zig").Rotation;
pub const Scale = @import("spatial.zig").Scale;

// Game logic components
pub const Health = @import("gameplay.zig").Health;
pub const Energy = @import("gameplay.zig").Energy;
pub const AI = @import("gameplay.zig").AI;
pub const Lifetime = @import("gameplay.zig").Lifetime;
pub const Timer = @import("gameplay.zig").Timer;

// Relationship components
pub const Tag = @import("relationships.zig").Tag;
pub const Parent = @import("relationships.zig").Parent;
pub const Children = @import("relationships.zig").Children;
