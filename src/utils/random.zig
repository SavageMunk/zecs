const std = @import("std");

/// Generate a random float in a range
pub fn randomFloat(min: f32, max: f32) f32 {
    return min + std.crypto.random.float(f32) * (max - min);
}

/// Generate a random integer in a range
pub fn randomInt(min: i32, max: i32) i32 {
    return min + @as(i32, @intCast(std.crypto.random.int(u32) % @as(u32, @intCast(max - min + 1))));
}

/// Generate a random boolean with given probability
pub fn randomBool(probability: f32) bool {
    return std.crypto.random.float(f32) < probability;
}

/// Generate a random direction vector (normalized)
pub fn randomDirection() struct { x: f32, y: f32 } {
    const angle = std.crypto.random.float(f32) * 2.0 * std.math.pi;
    return .{
        .x = @cos(angle),
        .y = @sin(angle),
    };
}

/// Generate a random position within a circle
pub fn randomInCircle(center_x: f32, center_y: f32, radius: f32) struct { x: f32, y: f32 } {
    const angle = std.crypto.random.float(f32) * 2.0 * std.math.pi;
    const r = @sqrt(std.crypto.random.float(f32)) * radius;
    
    return .{
        .x = center_x + r * @cos(angle),
        .y = center_y + r * @sin(angle),
    };
}

/// Generate a random position within a rectangle
pub fn randomInRect(min_x: f32, min_y: f32, max_x: f32, max_y: f32) struct { x: f32, y: f32 } {
    return .{
        .x = randomFloat(min_x, max_x),
        .y = randomFloat(min_y, max_y),
    };
}

test "random utilities" {
    // Test ranges
    for (0..100) |_| {
        const f = randomFloat(10.0, 20.0);
        try std.testing.expect(f >= 10.0 and f <= 20.0);
        
        const i = randomInt(5, 15);
        try std.testing.expect(i >= 5 and i <= 15);
    }
    
    // Test direction is normalized
    const dir = randomDirection();
    const magnitude = @sqrt(dir.x * dir.x + dir.y * dir.y);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), magnitude, 0.001);
}
