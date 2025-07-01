const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    _ = gpa.allocator(); // Not used yet but available for future use
    
    std.debug.print("=== SQLite Raw Performance Test ===\n", .{});
    
    // Open database
    var db: ?*c.sqlite3 = null;
    var rc = c.sqlite3_open(":memory:", &db);
    if (rc != c.SQLITE_OK) {
        std.debug.print("Can't open database: {s}\n", .{c.sqlite3_errmsg(db)});
        return;
    }
    defer _ = c.sqlite3_close(db);
    
    // Apply PRAGMA optimizations
    const pragmas = [_][]const u8{
        "PRAGMA journal_mode = WAL;",
        "PRAGMA synchronous = NORMAL;",
        "PRAGMA cache_size = -65536;", // 64MB cache
        "PRAGMA temp_store = MEMORY;",
        "PRAGMA mmap_size = 268435456;", // 256MB
        "PRAGMA foreign_keys = OFF;",
        "PRAGMA optimize;",
    };
    
    for (pragmas) |pragma| {
        rc = c.sqlite3_exec(db, pragma.ptr, null, null, null);
        if (rc != c.SQLITE_OK) {
            std.debug.print("PRAGMA failed: {s}\n", .{c.sqlite3_errmsg(db)});
        }
    }
    
    // Create simple test table
    const create_sql = "CREATE TABLE test_updates (id INTEGER PRIMARY KEY, x REAL, y REAL);";
    rc = c.sqlite3_exec(db, create_sql, null, null, null);
    if (rc != c.SQLITE_OK) {
        std.debug.print("Create table failed: {s}\n", .{c.sqlite3_errmsg(db)});
        return;
    }
    
    // Insert test data
    const insert_count = 6000; // Same as moving entities
    
    std.debug.print("Inserting {d} test records...\n", .{insert_count});
    
    rc = c.sqlite3_exec(db, "BEGIN TRANSACTION;", null, null, null);
    if (rc != c.SQLITE_OK) return;
    
    const insert_sql = "INSERT INTO test_updates (x, y) VALUES (?, ?);";
    var insert_stmt: ?*c.sqlite3_stmt = null;
    rc = c.sqlite3_prepare_v2(db, insert_sql, -1, &insert_stmt, null);
    if (rc != c.SQLITE_OK) return;
    defer _ = c.sqlite3_finalize(insert_stmt);
    
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();
    
    for (0..insert_count) |_| {
        rc = c.sqlite3_bind_double(insert_stmt, 1, random.float(f64) * 1000.0);
        if (rc != c.SQLITE_OK) return;
        rc = c.sqlite3_bind_double(insert_stmt, 2, random.float(f64) * 1000.0);
        if (rc != c.SQLITE_OK) return;
        
        rc = c.sqlite3_step(insert_stmt);
        if (rc != c.SQLITE_DONE) return;
        
        _ = c.sqlite3_reset(insert_stmt);
    }
    
    rc = c.sqlite3_exec(db, "COMMIT;", null, null, null);
    if (rc != c.SQLITE_OK) return;
    
    std.debug.print("Test data inserted successfully.\n", .{});
    
    // Test 1: Simple UPDATE with WHERE
    std.debug.print("\\nTest 1: Simple UPDATE with prepared statement...\n", .{});
    const update_sql = "UPDATE test_updates SET x = x + ?, y = y + ? WHERE id = ?;";
    var update_stmt: ?*c.sqlite3_stmt = null;
    rc = c.sqlite3_prepare_v2(db, update_sql, -1, &update_stmt, null);
    if (rc != c.SQLITE_OK) return;
    defer _ = c.sqlite3_finalize(update_stmt);
    
    const dt = 1.0 / 60.0;
    const ticks = 60;
    var total_updates: u32 = 0;
    
    const start_time = std.time.nanoTimestamp();
    
    for (0..ticks) |_| {
        rc = c.sqlite3_exec(db, "BEGIN TRANSACTION;", null, null, null);
        if (rc != c.SQLITE_OK) return;
        
        for (1..insert_count + 1) |id| {
            const dx = (random.float(f64) - 0.5) * 100.0 * dt;
            const dy = (random.float(f64) - 0.5) * 100.0 * dt;
            
            rc = c.sqlite3_bind_double(update_stmt, 1, dx);
            if (rc != c.SQLITE_OK) return;
            rc = c.sqlite3_bind_double(update_stmt, 2, dy);
            if (rc != c.SQLITE_OK) return;
            rc = c.sqlite3_bind_int64(update_stmt, 3, @intCast(id));
            if (rc != c.SQLITE_OK) return;
            
            rc = c.sqlite3_step(update_stmt);
            if (rc != c.SQLITE_DONE) return;
            
            _ = c.sqlite3_reset(update_stmt);
            total_updates += 1;
        }
        
        rc = c.sqlite3_exec(db, "COMMIT;", null, null, null);
        if (rc != c.SQLITE_OK) return;
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration_ns = @as(u64, @intCast(end_time - start_time));
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    const updates_per_second = @as(f64, @floatFromInt(total_updates)) / (duration_ms / 1000.0);
    
    std.debug.print("  Updated {d} records in {d:.2}ms\n", .{ total_updates, duration_ms });
    std.debug.print("  Rate: {d:.0} updates/second\n", .{updates_per_second});
    
    // Test 2: Batch UPDATE without transaction per tick
    std.debug.print("\\nTest 2: Batch UPDATE without per-tick transactions...\n", .{});
    
    const start_time2 = std.time.nanoTimestamp();
    total_updates = 0;
    
    for (0..ticks) |_| {
        for (1..insert_count + 1) |id| {
            const dx = (random.float(f64) - 0.5) * 100.0 * dt;
            const dy = (random.float(f64) - 0.5) * 100.0 * dt;
            
            rc = c.sqlite3_bind_double(update_stmt, 1, dx);
            if (rc != c.SQLITE_OK) return;
            rc = c.sqlite3_bind_double(update_stmt, 2, dy);
            if (rc != c.SQLITE_OK) return;
            rc = c.sqlite3_bind_int64(update_stmt, 3, @intCast(id));
            if (rc != c.SQLITE_OK) return;
            
            rc = c.sqlite3_step(update_stmt);
            if (rc != c.SQLITE_DONE) return;
            
            _ = c.sqlite3_reset(update_stmt);
            total_updates += 1;
        }
    }
    
    const end_time2 = std.time.nanoTimestamp();
    const duration_ns2 = @as(u64, @intCast(end_time2 - start_time2));
    const duration_ms2 = @as(f64, @floatFromInt(duration_ns2)) / 1_000_000.0;
    const updates_per_second2 = @as(f64, @floatFromInt(total_updates)) / (duration_ms2 / 1000.0);
    
    std.debug.print("  Updated {d} records in {d:.2}ms\n", .{ total_updates, duration_ms2 });
    std.debug.print("  Rate: {d:.0} updates/second\n", .{updates_per_second2});
    
    std.debug.print("\\nSpeedup without transactions: {d:.1}x\\n", .{updates_per_second2 / updates_per_second});
}
