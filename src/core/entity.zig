const std = @import("std");

/// Entity ID type - simple integer for now
pub const EntityId = u32;

/// Invalid entity constant
pub const INVALID_ENTITY: EntityId = 0;

/// Generate the next available entity ID
pub fn nextEntityId(current_max: EntityId) EntityId {
    return current_max + 1;
}

/// Check if an entity ID is valid
pub fn isValidEntity(entity_id: EntityId) bool {
    return entity_id != INVALID_ENTITY;
}

test "entity ID validation" {
    try std.testing.expect(isValidEntity(1));
    try std.testing.expect(!isValidEntity(INVALID_ENTITY));
}

test "entity ID generation" {
    try std.testing.expectEqual(@as(EntityId, 1), nextEntityId(0));
    try std.testing.expectEqual(@as(EntityId, 10), nextEntityId(9));
}
