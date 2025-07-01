const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Add zsqlite dependency
    const zsqlite_dep = b.dependency("zsqlite", .{
        .target = target,
        .optimize = optimize,
    });

    // Library target
    const lib = b.addStaticLibrary(.{
        .name = "zecs",
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    // Add zsqlite module to our library
    lib.root_module.addImport("zsqlite", zsqlite_dep.module("zsqlite"));
    lib.linkLibC();
    lib.linkSystemLibrary("sqlite3");
    
    b.installArtifact(lib);

    // Demo executable (shows how to use the library)
    const demo = b.addExecutable(.{
        .name = "zecs-demo",
        .root_source_file = b.path("examples/demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    demo.root_module.addImport("zecs", lib.root_module);
    demo.root_module.addImport("zsqlite", zsqlite_dep.module("zsqlite"));
    demo.linkLibC();
    demo.linkSystemLibrary("sqlite3");
    b.installArtifact(demo);

    // Ecosystem simulation example
    const ecosystem = b.addExecutable(.{
        .name = "ecosystem",
        .root_source_file = b.path("examples/ecosystem.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    ecosystem.root_module.addImport("zecs", lib.root_module);
    ecosystem.root_module.addImport("zsqlite", zsqlite_dep.module("zsqlite"));
    ecosystem.linkLibC();
    ecosystem.linkSystemLibrary("sqlite3");
    
    // Performance benchmark
    const bench = b.addExecutable(.{
        .name = "bench",
        .root_source_file = b.path("benchmarks/performance.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    bench.root_module.addImport("zecs", lib.root_module);
    bench.root_module.addImport("zsqlite", zsqlite_dep.module("zsqlite"));
    bench.linkLibC();
    bench.linkSystemLibrary("sqlite3");

    // SQLite Performance benchmark
    const sqlite_bench = b.addExecutable(.{
        .name = "sqlite-bench",
        .root_source_file = b.path("benchmarks/sqlite_performance.zig"),
        .target = target,
        .optimize = optimize,
    });
    
    sqlite_bench.root_module.addImport("zecs", lib.root_module);
    sqlite_bench.root_module.addImport("zsqlite", zsqlite_dep.module("zsqlite"));
    sqlite_bench.linkLibC();
    sqlite_bench.linkSystemLibrary("sqlite3");

    // Raw SQLite Performance Test
    const raw_sqlite_test = b.addExecutable(.{
        .name = "raw-sqlite-test",
        .root_source_file = b.path("raw_sqlite_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    raw_sqlite_test.root_module.addImport("zsqlite", zsqlite_dep.module("zsqlite"));
    raw_sqlite_test.linkLibC();
    raw_sqlite_test.linkSystemLibrary("sqlite3");

    // Multi-threaded test
    const multi_thread_test = b.addExecutable(.{
        .name = "multi-thread-test",
        .root_source_file = b.path("multi_thread_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    multi_thread_test.root_module.addImport("zecs", lib.root_module);
    multi_thread_test.root_module.addImport("zsqlite", zsqlite_dep.module("zsqlite"));
    multi_thread_test.linkLibC();
    multi_thread_test.linkSystemLibrary("sqlite3");

    // Comprehensive performance demo
    const comprehensive_demo = b.addExecutable(.{
        .name = "comprehensive-demo",
        .root_source_file = b.path("comprehensive_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    comprehensive_demo.root_module.addImport("zecs", lib.root_module);
    comprehensive_demo.root_module.addImport("zsqlite", zsqlite_dep.module("zsqlite"));
    comprehensive_demo.linkLibC();
    comprehensive_demo.linkSystemLibrary("sqlite3");

    // Game of Life benchmark
    const game_of_life = b.addExecutable(.{
        .name = "game-of-life",
        .root_source_file = b.path("game_of_life.zig"),
        .target = target,
        .optimize = optimize,
    });
    game_of_life.root_module.addImport("zecs", lib.root_module);
    game_of_life.root_module.addImport("zsqlite", zsqlite_dep.module("zsqlite"));
    game_of_life.linkLibC();
    game_of_life.linkSystemLibrary("sqlite3");

    // Optimized Game of Life benchmark
    const game_of_life_optimized = b.addExecutable(.{
        .name = "game-of-life-optimized",
        .root_source_file = b.path("game_of_life_optimized.zig"),
        .target = target,
        .optimize = optimize,
    });
    game_of_life_optimized.root_module.addImport("zecs", lib.root_module);
    game_of_life_optimized.root_module.addImport("zsqlite", zsqlite_dep.module("zsqlite"));
    game_of_life_optimized.linkLibC();
    game_of_life_optimized.linkSystemLibrary("sqlite3");
    b.installArtifact(game_of_life_optimized);

    // Comprehensive Game of Life benchmark (tests multiple modes)
    const game_of_life_comprehensive = b.addExecutable(.{
        .name = "game-of-life-comprehensive",
        .root_source_file = b.path("game_of_life_comprehensive.zig"),
        .target = target,
        .optimize = optimize,
    });
    game_of_life_comprehensive.root_module.addImport("zecs", lib.root_module);
    game_of_life_comprehensive.root_module.addImport("zsqlite", zsqlite_dep.module("zsqlite"));
    game_of_life_comprehensive.linkLibC();
    game_of_life_comprehensive.linkSystemLibrary("sqlite3");
    b.installArtifact(game_of_life_comprehensive);

    // Raw ECS Performance Benchmark
    const raw_ecs_benchmark = b.addExecutable(.{
        .name = "raw-ecs-benchmark",
        .root_source_file = b.path("raw_ecs_benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });
    raw_ecs_benchmark.root_module.addImport("zecs", lib.root_module);
    raw_ecs_benchmark.root_module.addImport("zsqlite", zsqlite_dep.module("zsqlite"));
    raw_ecs_benchmark.linkLibC();
    raw_ecs_benchmark.linkSystemLibrary("sqlite3");
    b.installArtifact(raw_ecs_benchmark);

    // Game of Life TimeSkip benchmark
    const game_of_life_timeskip = b.addExecutable(.{
        .name = "game-of-life-timeskip",
        .root_source_file = b.path("game_of_life_timeskip.zig"),
        .target = target,
        .optimize = optimize,
    });
    game_of_life_timeskip.root_module.addImport("zecs", lib.root_module);
    game_of_life_timeskip.root_module.addImport("zsqlite", zsqlite_dep.module("zsqlite"));
    game_of_life_timeskip.linkLibC();
    game_of_life_timeskip.linkSystemLibrary("sqlite3");
    b.installArtifact(game_of_life_timeskip);

    // Run steps
    const run_demo = b.addRunArtifact(demo);
    const run_ecosystem = b.addRunArtifact(ecosystem);
    const run_bench = b.addRunArtifact(bench);
    const run_sqlite_bench = b.addRunArtifact(sqlite_bench);
    const run_raw_sqlite_test = b.addRunArtifact(raw_sqlite_test);
    const run_multi_thread_test = b.addRunArtifact(multi_thread_test);
    const run_game_of_life = b.addRunArtifact(game_of_life);
    const run_game_of_life_optimized = b.addRunArtifact(game_of_life_optimized);
    const run_game_of_life_comprehensive = b.addRunArtifact(game_of_life_comprehensive);
    const run_comprehensive_demo = b.addRunArtifact(comprehensive_demo);
    const run_raw_ecs_benchmark = b.addRunArtifact(raw_ecs_benchmark);
    const run_game_of_life_timeskip = b.addRunArtifact(game_of_life_timeskip);

    const demo_step = b.step("demo", "Run the basic demo");
    demo_step.dependOn(&run_demo.step);
    
    const ecosystem_step = b.step("ecosystem", "Run the ecosystem simulation");
    ecosystem_step.dependOn(&run_ecosystem.step);
    
    const bench_step = b.step("bench", "Run performance benchmarks");
    bench_step.dependOn(&run_bench.step);

    const sqlite_bench_step = b.step("sqlite-bench", "Run SQLite performance benchmarks");
    sqlite_bench_step.dependOn(&run_sqlite_bench.step);

    const raw_sqlite_test_step = b.step("raw-sqlite-test", "Run raw SQLite performance test");
    raw_sqlite_test_step.dependOn(&run_raw_sqlite_test.step);

    const multi_thread_test_step = b.step("multi-thread-test", "Run multi-threaded ECS test");
    multi_thread_test_step.dependOn(&run_multi_thread_test.step);

    const comprehensive_demo_step = b.step("comprehensive-demo", "Run comprehensive performance demo");
    comprehensive_demo_step.dependOn(&run_comprehensive_demo.step);

    const game_of_life_step = b.step("game-of-life", "Run Game of Life benchmark");
    game_of_life_step.dependOn(&run_game_of_life.step);

    const game_of_life_optimized_step = b.step("game-of-life-optimized", "Run optimized Game of Life benchmark");
    game_of_life_optimized_step.dependOn(&run_game_of_life_optimized.step);

    const game_of_life_comprehensive_step = b.step("game-of-life-comprehensive", "Run comprehensive Game of Life benchmark");
    game_of_life_comprehensive_step.dependOn(&run_game_of_life_comprehensive.step);

    const raw_ecs_benchmark_step = b.step("raw-ecs-benchmark", "Run raw ECS performance benchmark");
    raw_ecs_benchmark_step.dependOn(&run_raw_ecs_benchmark.step);

    const game_of_life_timeskip_step = b.step("game-of-life-timeskip", "Run Game of Life with TimeSkip benchmark");
    game_of_life_timeskip_step.dependOn(&run_game_of_life_timeskip.step);

    // Tests
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_tests.root_module.addImport("zsqlite", zsqlite_dep.module("zsqlite"));
    lib_tests.linkLibC();
    lib_tests.linkSystemLibrary("sqlite3");

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&b.addRunArtifact(lib_tests).step);
}
