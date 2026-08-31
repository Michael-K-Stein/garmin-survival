import Toybox.Lang;

//! Every tunable number in the game. Nothing in the simulation hardcodes a
//! cost, a rate or a position: balance passes live here so they can be
//! retuned without touching the systems that read them.
//!
//! The four areas are described by parallel arrays indexed by area id. That
//! is clumsier to read than one record per area would be, but Monkey C has no
//! struct type and a dictionary of mixed-type values fights the type checker,
//! so the arrays stay flat and each one is documented where it is declared.
module Balance {

    // --- The board ------------------------------------------------------
    //! Node positions are authored for a 416x416 round face and scaled to the
    //! real display in Layout. Every area uses the same three sites, so the
    //! player's muscle memory carries across areas.
    const NODES = [[112, 166], [304, 166], [208, 118]];
    const STORAGE = [120, 272];
    const MACHINE = [296, 272];
    const PLAYER_START = [208, 212];

    //! Anything within this radius of an object counts as a tap on it. The
    //! spec asks for ~60px targets; 48px of radius is a 96px circle.
    const TAP_RADIUS = 48;
    //! How close an actor must get before it starts working.
    const ARRIVE = 10;

    // --- Areas ----------------------------------------------------------
    const AREA_COUNT = 4;
    const FOREST = 0;
    const QUARRY = 1;
    const MINE = 2;
    const FIELD = 3;

    const AREA_NAME = ["FOREST", "QUARRY", "MINE", "FLAX FIELD"];
    const RESOURCE_NAME = ["wood", "stone", "iron", "fiber"];
    //! How each area's nodes are drawn: tree, boulder, ore seam, flax stand.
    const NODE_KIND = [0, 1, 2, 3];
    //! Cash for one unit sold raw at the yard.
    const RESOURCE_VALUE = [6.0, 15.0, 40.0, 110.0];
    const NODE_MAX = [20, 24, 30, 36];
    const NODE_RESPAWN = [30.0, 40.0, 55.0, 70.0];
    //! Cash to open the area. The first one is free.
    const AREA_UNLOCK = [0.0, 2500.0, 60000.0, 900000.0];

    // --- Machines -------------------------------------------------------
    const MACHINE_NAME = ["LUMBER MILL", "STONE CUTTER", "SMELTER", "LOOM"];
    const PRODUCT_NAME = ["planks", "blocks", "ingots", "cloth"];
    //! Raw units eaten per second at level 1.
    const MACHINE_RATE = [0.60, 0.50, 0.40, 0.35];
    //! Cost of building one; upgrades follow COST_GROWTH from there.
    const MACHINE_COST = [750.0, 6000.0, 60000.0, 700000.0];
    //! Extra throughput per level after the first, as a fraction of base.
    const MACHINE_RATE_STEP = 0.55;
    //! A finished product is worth this much more than the raw material.
    const MACHINE_VALUE = 2.2;
    const MACHINE_VALUE_STEP = 0.15;
    //! Batch size, for the progress bar and the "10 in, 5 out" readout.
    const MACHINE_BATCH = 10;
    const MACHINE_YIELD = 5;

    // --- Player ---------------------------------------------------------
    const PLAYER_SPEED = 58.0;          // px/sec at level 0
    const PLAYER_SPEED_STEP = 0.18;     // +18% of base per level
    const PLAYER_CAPACITY = 20;
    const PLAYER_CAPACITY_STEP = 10;
    const PLAYER_COLLECT = 2.0;         // units/sec at level 0
    const PLAYER_COLLECT_STEP = 0.30;
    //! Fraction faster every node on every board refills, per level.
    const PLAYER_REGROW_STEP = 0.15;

    const COST_SPEED = 120.0;
    const COST_CAPACITY = 150.0;
    const COST_COLLECT = 100.0;
    const COST_REGROW = 400.0;

    // --- Workers --------------------------------------------------------
    //! Per area, so a fully staffed operation is 24 people.
    const WORKER_MAX = 6;
    const WORKER_SPEED = 42.0;
    const WORKER_SPEED_STEP = 0.20;
    const WORKER_CAPACITY = 12;
    const WORKER_CAPACITY_STEP = 6;
    const WORKER_COLLECT = 1.2;
    const WORKER_COLLECT_STEP = 0.25;

    //! Hiring is priced off the whole payroll, so later areas start dear.
    const COST_HIRE = 400.0;
    const COST_WORKER_SPEED = 500.0;
    const COST_WORKER_CAPACITY = 600.0;

    // --- Economy --------------------------------------------------------
    //! cost = base * COST_GROWTH^level, per the spec's exponential curve.
    const COST_GROWTH = 1.55;
    const HIRE_GROWTH = 1.90;

    // --- Idle / offline -------------------------------------------------
    const MAX_OFFLINE_SECS = 8 * 3600;
    const MIN_OFFLINE_SECS = 60;
    //! Nobody works quite as hard when the watch is in a pocket.
    const OFFLINE_EFFICIENCY = 0.6;
    //! Round-trip distance a worker walks, used to price offline output
    //! without simulating a single step of it.
    const OFFLINE_TRIP_PX = 260.0;

    const AUTOSAVE_SECS = 20.0;
    //! Simulation cadence while a view is on screen.
    const TICK_MS = 100;

    //! Seconds an area's name stays on screen after a swipe.
    const AREA_LABEL_SECS = 1.6;
}
