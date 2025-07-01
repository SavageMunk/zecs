const std = @import("std");
const zsqlite = @import("zsqlite");
const c = zsqlite.c;
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const EntityId = @import("entity.zig").EntityId;

/// SQLite-powered ECS World for high-performance batch operations
pub const SqliteWorld = struct {
    const Self = @This();
    
    db: ?*c.sqlite3,
    allocator: Allocator,
    
    // Prepared statements for performance
    insert_entity_stmt: ?*c.sqlite3_stmt,
    insert_component_stmt: ?*c.sqlite3_stmt,
    query_components_stmt: ?*c.sqlite3_stmt,
    update_component_stmt: ?*c.sqlite3_stmt,
    delete_entity_stmt: ?*c.sqlite3_stmt,
    
    next_entity_id: EntityId,
    
    pub fn init(allocator: Allocator, db_path: ?[]const u8) !Self {
        // Open database (in-memory if no path provided)
        const path = db_path orelse ":memory:";
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path.ptr, &db);
        
        if (rc != c.SQLITE_OK) {
            std.debug.print("Failed to open database: {s}\n", .{c.sqlite3_errmsg(db)});
            return error.SQLiteOpenFailed;
        }
        
        var world = Self{
            .db = db,
            .allocator = allocator,
            .insert_entity_stmt = null,
            .insert_component_stmt = null,
            .query_components_stmt = null,
            .update_component_stmt = null,
            .delete_entity_stmt = null,
            .next_entity_id = 1,
        };
        
        try world.createTables();
        try world.prepareStatements();
        
        return world;
    }
    
    pub fn deinit(self: *Self) void {
        if (self.insert_entity_stmt) |stmt| _ = c.sqlite3_finalize(stmt);
        if (self.insert_component_stmt) |stmt| _ = c.sqlite3_finalize(stmt);
        if (self.query_components_stmt) |stmt| _ = c.sqlite3_finalize(stmt);
        if (self.update_component_stmt) |stmt| _ = c.sqlite3_finalize(stmt);
        if (self.delete_entity_stmt) |stmt| _ = c.sqlite3_finalize(stmt);
        if (self.db) |db| _ = c.sqlite3_close(db);
    }
    
    /// Create the ECS tables optimized for batch operations
    fn createTables(self: *Self) !void {
        // Enable optimizations for batch operations
        var errmsg: [*c]u8 = null;
        
        // Entities table
        const entities_sql = 
            \\CREATE TABLE IF NOT EXISTS entities (
            \\    id INTEGER PRIMARY KEY,
            \\    created_at INTEGER DEFAULT (unixepoch()),
            \\    active INTEGER DEFAULT 1
            \\);
        ;
        
        var rc = c.sqlite3_exec(self.db, entities_sql, null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            std.debug.print("Error creating entities table: {s}\n", .{errmsg});
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        // Components table with optimized schema for batch queries
        const components_sql = 
            \\CREATE TABLE IF NOT EXISTS components (
            \\    entity_id INTEGER NOT NULL,
            \\    component_type INTEGER NOT NULL,
            \\    x REAL,
            \\    y REAL,
            \\    z REAL,
            \\    dx REAL,
            \\    dy REAL,
            \\    dz REAL,
            \\    health_current INTEGER,
            \\    health_max INTEGER,
            \\    energy_current REAL,
            \\    energy_max REAL,
            \\    ai_state INTEGER,
            \\    ai_target INTEGER,
            \\    data BLOB,
            \\    PRIMARY KEY (entity_id, component_type),
            \\    FOREIGN KEY (entity_id) REFERENCES entities(id)
            \\);
        ;
        
        rc = c.sqlite3_exec(self.db, components_sql, null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            std.debug.print("Error creating components table: {s}\n", .{errmsg});
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        // Indexes for fast queries
        const indexes = [_][]const u8{
            "CREATE INDEX IF NOT EXISTS idx_components_type ON components(component_type);",
            "CREATE INDEX IF NOT EXISTS idx_components_entity ON components(entity_id);",
            "CREATE INDEX IF NOT EXISTS idx_position ON components(component_type, x, y) WHERE component_type = 1;",
            "CREATE INDEX IF NOT EXISTS idx_velocity ON components(component_type, dx, dy) WHERE component_type = 2;",
            "CREATE INDEX IF NOT EXISTS idx_health ON components(component_type, health_current) WHERE component_type = 3;",
        };
        
        for (indexes) |index_sql| {
            rc = c.sqlite3_exec(self.db, index_sql.ptr, null, null, &errmsg);
            if (rc != c.SQLITE_OK) {
                std.debug.print("Error creating index: {s}\n", .{errmsg});
                if (errmsg != null) c.sqlite3_free(errmsg);
                return error.SQLiteExecFailed;
            }
        }
    }
    
    /// Prepare statements for high-performance operations
    fn prepareStatements(self: *Self) !void {
        var rc = c.sqlite3_prepare_v2(self.db, "INSERT INTO entities (id) VALUES (?)", -1, &self.insert_entity_stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        
        rc = c.sqlite3_prepare_v2(self.db, 
            \\INSERT OR REPLACE INTO components 
            \\(entity_id, component_type, x, y, z, dx, dy, dz, health_current, health_max, energy_current, energy_max, ai_state, ai_target, data)
            \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        , -1, &self.insert_component_stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        
        rc = c.sqlite3_prepare_v2(self.db, 
            \\SELECT entity_id, x, y, dx, dy, health_current, health_max 
            \\FROM components 
            \\WHERE component_type IN (?, ?)
        , -1, &self.query_components_stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        
        rc = c.sqlite3_prepare_v2(self.db, 
            \\UPDATE components 
            \\SET x = ?, y = ?, dx = ?, dy = ?, health_current = ?, energy_current = ?
            \\WHERE entity_id = ? AND component_type = ?
        , -1, &self.update_component_stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        
        rc = c.sqlite3_prepare_v2(self.db, "UPDATE entities SET active = 0 WHERE id = ?", -1, &self.delete_entity_stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
    }
    
    /// Create a new entity
    pub fn createEntity(self: *Self) !EntityId {
        const entity_id = self.next_entity_id;
        self.next_entity_id += 1;
        
        try self.insert_entity_stmt.?.exec(.{entity_id});
        return entity_id;
    }
    
    /// Batch create multiple entities
    pub fn createEntities(self: *Self, count: u32) ![]EntityId {
        var entities = try self.allocator.alloc(EntityId, count);
        
        try self.db.exec("BEGIN TRANSACTION;", .{});
        defer self.db.exec("COMMIT;", .{}) catch {};
        
        for (0..count) |i| {
            entities[i] = try self.createEntity();
        }
        
        return entities;
    }
    
    /// Add position component (optimized for spatial data)
    pub fn addPosition(self: *Self, entity_id: EntityId, x: f32, y: f32) !void {
        try self.insert_component_stmt.?.exec(.{
            entity_id, 1, // component_type = 1 for Position
            x, y, null, // position data
            null, null, null, // velocity data
            null, null, // health data
            null, null, // energy data
            null, null, // ai data
            null // blob data
        });
    }
    
    /// Add velocity component
    pub fn addVelocity(self: *Self, entity_id: EntityId, dx: f32, dy: f32) !void {
        try self.insert_component_stmt.?.exec(.{
            entity_id, 2, // component_type = 2 for Velocity
            null, null, null, // position data
            dx, dy, null, // velocity data
            null, null, // health data
            null, null, // energy data
            null, null, // ai data
            null // blob data
        });
    }
    
    /// Add health component
    pub fn addHealth(self: *Self, entity_id: EntityId, current: i32, max: i32) !void {
        try self.insert_component_stmt.?.exec(.{
            entity_id, 3, // component_type = 3 for Health
            null, null, null, // position data
            null, null, null, // velocity data
            current, max, // health data
            null, null, // energy data
            null, null, // ai data
            null // blob data
        });
    }
    
    /// Batch movement system using SQL
    pub fn batchMovementSystem(self: *Self, dt: f32) !void {
        // Update all positions based on velocities in a single SQL statement
        try self.db.exec(
            \\UPDATE components 
            \\SET x = x + (
            \\    SELECT dx FROM components v 
            \\    WHERE v.entity_id = components.entity_id AND v.component_type = 2
            \\) * ?1,
            \\y = y + (
            \\    SELECT dy FROM components v 
            \\    WHERE v.entity_id = components.entity_id AND v.component_type = 2
            \\) * ?1
            \\WHERE component_type = 1 
            \\AND EXISTS (
            \\    SELECT 1 FROM components v 
            \\    WHERE v.entity_id = components.entity_id AND v.component_type = 2
            \\);
        , .{dt});
    }
    
    /// Batch health system using SQL
    pub fn batchHealthSystem(self: *Self, dt: f32) !void {
        // Regenerate health for all entities
        try self.db.exec(
            \\UPDATE components 
            \\SET health_current = MIN(health_current + CAST(1.0 * ?1 AS INTEGER), health_max)
            \\WHERE component_type = 3 AND health_current < health_max;
        , .{dt});
        
        // Remove dead entities
        try self.db.exec(
            \\UPDATE entities 
            \\SET active = 0 
            \\WHERE id IN (
            \\    SELECT entity_id FROM components 
            \\    WHERE component_type = 3 AND health_current <= 0
            \\);
        , .{});
    }
    
    /// Get movement data for custom processing
    pub fn getMovementData(self: *Self, allocator: Allocator) ![]MovementData {
        var stmt = try self.db.prepare("SELECT entity_id, x, y, dx, dy FROM movement_entities");
        defer stmt.deinit();
        
        var results = ArrayList(MovementData).init(allocator);
        
        var rows = try stmt.query(.{});
        while (try rows.next()) |row| {
            try results.append(MovementData{
                .entity_id = row.integer(0),
                .x = @floatCast(row.real(1)),
                .y = @floatCast(row.real(2)),
                .dx = @floatCast(row.real(3)),
                .dy = @floatCast(row.real(4)),
            });
        }
        
        return results.toOwnedSlice();
    }
    
    /// Get entity count
    pub fn getEntityCount(self: *Self) !u32 {
        var stmt = try self.db.prepare("SELECT COUNT(*) FROM entities WHERE active = 1");
        defer stmt.deinit();
        
        var rows = try stmt.query(.{});
        if (try rows.next()) |row| {
            return @intCast(row.integer(0));
        }
        return 0;
    }
    
    /// Get component count
    pub fn getComponentCount(self: *Self) !u32 {
        var stmt = try self.db.prepare("SELECT COUNT(*) FROM components");
        defer stmt.deinit();
        
        var rows = try stmt.query(.{});
        if (try rows.next()) |row| {
            return @intCast(row.integer(0));
        }
        return 0;
    }
    
    /// BATCH OPERATIONS FOR HIGH PERFORMANCE
    
    /// Batch create entities (much faster than individual creates)
    pub fn batchCreateEntities(self: *Self, count: u32) !ArrayList(EntityId) {
        var entities = ArrayList(EntityId).init(self.allocator);
        
        // Start transaction for batch operation
        try self.db.exec("BEGIN TRANSACTION;", .{});
        defer self.db.exec("COMMIT;", .{}) catch {};
        
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const entity_id = self.next_entity_id;
            self.next_entity_id += 1;
            
            try self.insert_entity_stmt.?.bind(1, entity_id);
            try self.insert_entity_stmt.?.step();
            try entities.append(entity_id);
            try self.insert_entity_stmt.?.reset();
        }
        
        try self.db.exec("COMMIT;", .{});
        return entities;
    }
    
    /// Batch add components using a single transaction
    pub fn batchAddPositionVelocity(self: *Self, entities: []const EntityId, positions: []const [2]f32, velocities: []const [2]f32) !void {
        if (entities.len != positions.len or entities.len != velocities.len) {
            return error.MismatchedArrayLengths;
        }
        
        // Start transaction
        try self.db.exec("BEGIN TRANSACTION;", .{});
        defer self.db.exec("COMMIT;", .{}) catch {};
        
        for (entities, positions, velocities) |entity_id, pos, vel| {
            // Add Position component
            try self.insert_component_stmt.?.bind(1, entity_id);
            try self.insert_component_stmt.?.bind(2, @as(i32, 1)); // Position type ID
            try self.insert_component_stmt.?.bind(3, pos[0]); // x
            try self.insert_component_stmt.?.bind(4, pos[1]); // y
            try self.insert_component_stmt.?.bind(5, null); // dx
            try self.insert_component_stmt.?.bind(6, null); // dy
            try self.insert_component_stmt.?.bind(7, null); // health_current
            try self.insert_component_stmt.?.bind(8, null); // health_max
            try self.insert_component_stmt.?.step();
            try self.insert_component_stmt.?.reset();
            
            // Add Velocity component
            try self.insert_component_stmt.?.bind(1, entity_id);
            try self.insert_component_stmt.?.bind(2, @as(i32, 2)); // Velocity type ID
            try self.insert_component_stmt.?.bind(3, null); // x
            try self.insert_component_stmt.?.bind(4, null); // y
            try self.insert_component_stmt.?.bind(5, vel[0]); // dx
            try self.insert_component_stmt.?.bind(6, vel[1]); // dy
            try self.insert_component_stmt.?.bind(7, null); // health_current
            try self.insert_component_stmt.?.bind(8, null); // health_max
            try self.insert_component_stmt.?.step();
            try self.insert_component_stmt.?.reset();
        }
        
        try self.db.exec("COMMIT;", .{});
    }
    
    /// Batch movement update using SQL (MUCH faster than individual updates)
    pub fn batchMovementUpdate(self: *Self, dt: f32) !u32 {
        // Use SQL to update ALL positions at once using a JOIN
        const update_sql = 
            \\UPDATE components 
            \\SET x = x + (
            \\    SELECT dx FROM components v 
            \\    WHERE v.entity_id = components.entity_id 
            \\      AND v.component_type = 2
            \\) * ?,
            \\y = y + (
            \\    SELECT dy FROM components v 
            \\    WHERE v.entity_id = components.entity_id 
            \\      AND v.component_type = 2
            \\) * ?
            \\WHERE component_type = 1
            \\  AND EXISTS (
            \\    SELECT 1 FROM components v 
            \\    WHERE v.entity_id = components.entity_id 
            \\      AND v.component_type = 2
            \\  );
        ;
        
        var stmt = try self.db.prepare(update_sql);
        defer stmt.deinit();
        
        try stmt.bind(1, dt);
        try stmt.bind(2, dt);
        try stmt.step();
        
        return @intCast(self.db.changes());
    }
    
    /// Batch query all entities with Position + Velocity (returns all at once)
    pub fn batchQueryMovementEntities(self: *Self) !ArrayList(MovementData) {
        var result = ArrayList(MovementData).init(self.allocator);
        
        const query_sql = 
            \\SELECT 
            \\  p.entity_id, p.x, p.y, v.dx, v.dy
            \\FROM components p
            \\JOIN components v ON p.entity_id = v.entity_id
            \\WHERE p.component_type = 1 AND v.component_type = 2;
        ;
        
        var stmt = try self.db.prepare(query_sql);
        defer stmt.deinit();
        
        while (try stmt.next()) {
            const entity_data = MovementData{
                .entity_id = @intCast(stmt.getInt64(0)),
                .x = stmt.getFloat32(1),
                .y = stmt.getFloat32(2),
                .dx = stmt.getFloat32(3),
                .dy = stmt.getFloat32(4),
            };
            try result.append(entity_data);
        }
        
        return result;
    }
    
    /// Get performance statistics
    pub fn getBatchStats(self: *Self) !SqliteStats {
        var entity_stmt = try self.db.prepare("SELECT COUNT(*) FROM entities");
        defer entity_stmt.deinit();
        _ = try entity_stmt.next();
        const entity_count = entity_stmt.getInt64(0);
        
        var comp_stmt = try self.db.prepare("SELECT COUNT(*) FROM components");
        defer comp_stmt.deinit();
        _ = try comp_stmt.next();
        const component_count = comp_stmt.getInt64(0);
        
        // Get SQLite cache statistics
        var cache_stmt = try self.db.prepare("PRAGMA cache_size");
        defer cache_stmt.deinit();
        _ = try cache_stmt.next();
        const cache_size = cache_stmt.getInt64(0);
        
        return SqliteStats{
            .entity_count = @intCast(entity_count),
            .component_count = @intCast(component_count),
            .cache_hits = cache_size, // Simplified
            .cache_misses = 0,
        };
    }
};

/// Data structure for movement system batch processing
pub const MovementData = struct {
    entity_id: EntityId,
    x: f32,
    y: f32,
    dx: f32,
    dy: f32,
};

/// Performance statistics for SQLite ECS
pub const SqliteStats = struct {
    entity_count: u32,
    component_count: u32,
    cache_hits: i64,
    cache_misses: i64,
};
