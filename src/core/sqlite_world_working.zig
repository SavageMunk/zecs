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
            .next_entity_id = 1,
        };
        
        try world.createTables();
        try world.prepareStatements();
        
        return world;
    }
    
    pub fn deinit(self: *Self) void {
        if (self.insert_entity_stmt) |stmt| _ = c.sqlite3_finalize(stmt);
        if (self.insert_component_stmt) |stmt| _ = c.sqlite3_finalize(stmt);
        if (self.db) |db| _ = c.sqlite3_close(db);
    }
    
    /// Create the ECS tables optimized for batch operations
    fn createTables(self: *Self) !void {
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
    }
    
    /// Create a new entity
    pub fn createEntity(self: *Self) !EntityId {
        const entity_id = self.next_entity_id;
        self.next_entity_id += 1;
        
        var rc = c.sqlite3_bind_int64(self.insert_entity_stmt, 1, entity_id);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_step(self.insert_entity_stmt);
        if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
        
        _ = c.sqlite3_reset(self.insert_entity_stmt);
        return entity_id;
    }
    
    /// Batch create multiple entities
    pub fn createEntities(self: *Self, count: u32) ![]EntityId {
        var entities = try self.allocator.alloc(EntityId, count);
        
        var errmsg: [*c]u8 = null;
        var rc = c.sqlite3_exec(self.db, "BEGIN TRANSACTION;", null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        for (0..count) |i| {
            entities[i] = try self.createEntity();
        }
        
        rc = c.sqlite3_exec(self.db, "COMMIT;", null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        return entities;
    }
    
    /// Add position component (optimized for spatial data)
    pub fn addPosition(self: *Self, entity_id: EntityId, x: f32, y: f32) !void {
        var rc = c.sqlite3_bind_int64(self.insert_component_stmt, 1, entity_id);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_int(self.insert_component_stmt, 2, 1); // Position type
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_double(self.insert_component_stmt, 3, x);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_double(self.insert_component_stmt, 4, y);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        // Bind remaining parameters as NULL
        for (5..16) |i| {
            rc = c.sqlite3_bind_null(self.insert_component_stmt, @intCast(i));
            if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        }
        
        rc = c.sqlite3_step(self.insert_component_stmt);
        if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
        
        _ = c.sqlite3_reset(self.insert_component_stmt);
    }
    
    /// Add velocity component
    pub fn addVelocity(self: *Self, entity_id: EntityId, dx: f32, dy: f32) !void {
        var rc = c.sqlite3_bind_int64(self.insert_component_stmt, 1, entity_id);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_int(self.insert_component_stmt, 2, 2); // Velocity type
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        // Bind position as NULL
        for (3..5) |i| {
            rc = c.sqlite3_bind_null(self.insert_component_stmt, @intCast(i));
            if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        }
        
        rc = c.sqlite3_bind_null(self.insert_component_stmt, 5); // z position
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_double(self.insert_component_stmt, 6, dx);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_double(self.insert_component_stmt, 7, dy);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        // Bind remaining parameters as NULL
        for (8..16) |i| {
            rc = c.sqlite3_bind_null(self.insert_component_stmt, @intCast(i));
            if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        }
        
        rc = c.sqlite3_step(self.insert_component_stmt);
        if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
        
        _ = c.sqlite3_reset(self.insert_component_stmt);
    }
    
    /// Add health component
    pub fn addHealth(self: *Self, entity_id: EntityId, current: i32, max: i32) !void {
        var rc = c.sqlite3_bind_int64(self.insert_component_stmt, 1, entity_id);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_int(self.insert_component_stmt, 2, 3); // Health type
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        // Bind position and velocity as NULL
        for (3..8) |i| {
            rc = c.sqlite3_bind_null(self.insert_component_stmt, @intCast(i));
            if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        }
        
        rc = c.sqlite3_bind_null(self.insert_component_stmt, 8); // dz
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_int(self.insert_component_stmt, 9, current);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_int(self.insert_component_stmt, 10, max);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        // Bind remaining parameters as NULL
        for (11..16) |i| {
            rc = c.sqlite3_bind_null(self.insert_component_stmt, @intCast(i));
            if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        }
        
        rc = c.sqlite3_step(self.insert_component_stmt);
        if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
        
        _ = c.sqlite3_reset(self.insert_component_stmt);
    }
    
    /// BATCH OPERATIONS FOR HIGH PERFORMANCE
    
    /// Batch create entities (much faster than individual creates)
    pub fn batchCreateEntities(self: *Self, count: u32) !ArrayList(EntityId) {
        var entities = ArrayList(EntityId).init(self.allocator);
        
        var errmsg: [*c]u8 = null;
        var rc = c.sqlite3_exec(self.db, "BEGIN TRANSACTION;", null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        var i: u32 = 0;
        while (i < count) : (i += 1) {
            const entity_id = self.next_entity_id;
            self.next_entity_id += 1;
            
            rc = c.sqlite3_bind_int64(self.insert_entity_stmt, 1, entity_id);
            if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
            
            rc = c.sqlite3_step(self.insert_entity_stmt);
            if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
            
            try entities.append(entity_id);
            _ = c.sqlite3_reset(self.insert_entity_stmt);
        }
        
        rc = c.sqlite3_exec(self.db, "COMMIT;", null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        return entities;
    }
    
    /// Batch add components using a single transaction
    pub fn batchAddPositionVelocity(self: *Self, entities: []const EntityId, positions: []const [2]f32, velocities: []const [2]f32) !void {
        if (entities.len != positions.len or entities.len != velocities.len) {
            return error.MismatchedArrayLengths;
        }
        
        var errmsg: [*c]u8 = null;
        var rc = c.sqlite3_exec(self.db, "BEGIN TRANSACTION;", null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        for (entities, positions, velocities) |entity_id, pos, vel| {
            // Add Position component
            try self.addPosition(entity_id, pos[0], pos[1]);
            
            // Add Velocity component  
            try self.addVelocity(entity_id, vel[0], vel[1]);
        }
        
        rc = c.sqlite3_exec(self.db, "COMMIT;", null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
    }
    
    /// Batch movement update using SQL (MUCH faster than individual updates)
    pub fn batchMovementUpdate(self: *Self, dt: f32) !u32 {
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
        
        var stmt: ?*c.sqlite3_stmt = null;
        var rc = c.sqlite3_prepare_v2(self.db, update_sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        rc = c.sqlite3_bind_double(stmt, 1, dt);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_bind_double(stmt, 2, dt);
        if (rc != c.SQLITE_OK) return error.SQLiteBindFailed;
        
        rc = c.sqlite3_step(stmt);
        if (rc != c.SQLITE_DONE) return error.SQLiteStepFailed;
        
        return @intCast(c.sqlite3_changes(self.db));
    }
    
    /// Batch movement system using SQL
    pub fn batchMovementSystem(self: *Self, dt: f32) !void {
        _ = try self.batchMovementUpdate(dt);
    }
    
    /// Batch health system using SQL
    pub fn batchHealthSystem(self: *Self, dt: f32) !void {
        var errmsg: [*c]u8 = null;
        
        // Regenerate health for all entities
        const health_sql = "UPDATE components SET health_current = MIN(health_current + 1, health_max) WHERE component_type = 3 AND health_current < health_max;";
        var rc = c.sqlite3_exec(self.db, health_sql, null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        // Remove dead entities
        const dead_sql = "UPDATE entities SET active = 0 WHERE id IN (SELECT entity_id FROM components WHERE component_type = 3 AND health_current <= 0);";
        rc = c.sqlite3_exec(self.db, dead_sql, null, null, &errmsg);
        if (rc != c.SQLITE_OK) {
            if (errmsg != null) c.sqlite3_free(errmsg);
            return error.SQLiteExecFailed;
        }
        
        _ = dt; // Suppress unused parameter warning
    }
    
    /// Get performance statistics
    pub fn getStats(self: *Self) !SqliteStats {
        var stmt: ?*c.sqlite3_stmt = null;
        
        // Get entity count
        var rc = c.sqlite3_prepare_v2(self.db, "SELECT COUNT(*) FROM entities WHERE active = 1", -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        
        rc = c.sqlite3_step(stmt);
        const entity_count = if (rc == c.SQLITE_ROW) c.sqlite3_column_int64(stmt, 0) else 0;
        _ = c.sqlite3_finalize(stmt);
        
        // Get component count
        rc = c.sqlite3_prepare_v2(self.db, "SELECT COUNT(*) FROM components", -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.SQLitePrepareFailed;
        
        rc = c.sqlite3_step(stmt);
        const component_count = if (rc == c.SQLITE_ROW) c.sqlite3_column_int64(stmt, 0) else 0;
        _ = c.sqlite3_finalize(stmt);
        
        return SqliteStats{
            .entity_count = @intCast(entity_count),
            .component_count = @intCast(component_count),
            .cache_hits = 0, // Simplified
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
