const std = @import("std");

/// Calculate distance between two points
pub fn distance(x1: f32, y1: f32, x2: f32, y2: f32) f32 {
    const dx = x2 - x1;
    const dy = y2 - y1;
    return @sqrt(dx * dx + dy * dy);
}

/// Calculate squared distance (faster, avoid sqrt when just comparing)
pub fn distanceSquared(x1: f32, y1: f32, x2: f32, y2: f32) f32 {
    const dx = x2 - x1;
    const dy = y2 - y1;
    return dx * dx + dy * dy;
}

/// Normalize a vector
pub fn normalize(x: f32, y: f32) struct { x: f32, y: f32 } {
    const magnitude = @sqrt(x * x + y * y);
    if (magnitude == 0) return .{ .x = 0, .y = 0 };
    return .{ .x = x / magnitude, .y = y / magnitude };
}

/// Linear interpolation
pub fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

/// Clamp a value between min and max
pub fn clamp(value: f32, min_val: f32, max_val: f32) f32 {
    return @max(min_val, @min(max_val, value));
}

/// Wrap an angle to [0, 2π]
pub fn wrapAngle(angle: f32) f32 {
    var result = angle;
    while (result < 0) result += 2 * std.math.pi;
    while (result >= 2 * std.math.pi) result -= 2 * std.math.pi;
    return result;
}

/// Convert degrees to radians
pub fn toRadians(degrees: f32) f32 {
    return degrees * std.math.pi / 180.0;
}

/// Convert radians to degrees
pub fn toDegrees(radians: f32) f32 {
    return radians * 180.0 / std.math.pi;
}

/// Check if a point is inside a circle
pub fn pointInCircle(px: f32, py: f32, cx: f32, cy: f32, radius: f32) bool {
    return distanceSquared(px, py, cx, cy) <= radius * radius;
}

/// Check if a point is inside a rectangle
pub fn pointInRect(px: f32, py: f32, min_x: f32, min_y: f32, max_x: f32, max_y: f32) bool {
    return px >= min_x and px <= max_x and py >= min_y and py <= max_y;
}

test "math utilities" {
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), distance(0, 0, 3, 4), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), distanceSquared(0, 0, 3, 4), 0.001);
    
    const norm = normalize(3, 4);
    try std.testing.expectApproxEqAbs(@as(f32, 0.6), norm.x, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), norm.y, 0.001);
    
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), lerp(0, 10, 0.5), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 5.0), clamp(5, 0, 10), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), clamp(-5, 0, 10), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), clamp(15, 0, 10), 0.001);
}
