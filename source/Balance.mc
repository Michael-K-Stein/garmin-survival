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
    //! Chosen so 3 nodes' sustained regrowth (NODE_MAX / NODE_RESPAWN, summed)
    //! roughly matches what a full 6-worker crew plus the player can gather
    //! at level-0 stats - see tools/simulate_economy.py, which enforces this
    //! against demand so hiring past the node ceiling stops paying off.
    const NODE_RESPAWN = [11.0, 14.0, 20.0, 25.0];
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
    const PLAYER_REGROW_STEP = 0.20;

    const COST_SPEED = 120.0;
    const COST_CAPACITY = 150.0;
    const COST_COLLECT = 100.0;
    //! Priced against COST_WORKER_SPEED, not COST_SPEED: regrowth raises the
    //! node ceiling every gatherer draws against, so its payoff compounds
    //! with crew size the same way a crew-wide upgrade does.
    const COST_REGROW = 180.0;

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

    // --- Rich veins -----------------------------------------------------
    //! Every so often one site on the board the player is standing in comes
    //! in rich. Working it by hand yields several times as much per swing
    //! *without* draining the site any faster, which is the one thing in the
    //! game that beats the node ceiling - and the only way to get it is to be
    //! there and tap it. Crews walk straight past.
    const RICH_MULTIPLIER = 4.0;
    const RICH_SECS = 16.0;
    //! Seconds between flares, picked uniformly from this range.
    const RICH_GAP_MIN = 35.0;
    const RICH_GAP_SPAN = 55.0;

    // --- Area mastery ---------------------------------------------------
    //! Every unit an area realises - sold raw or run through its machine -
    //! counts toward that area's mastery. Mastery is a permanent multiplier
    //! on everything that area is worth, it is per-area rather than global,
    //! and it survives moving camp. It is the ladder that keeps climbing
    //! after the cash curve has outrun the wallet.
    const MASTERY_BASE = 900.0;
    const MASTERY_GROWTH = 1.45;
    const MASTERY_STEP = 0.10;

    // --- Contracts ------------------------------------------------------
    //! One open contract at a time, worked through in order, each a discrete
    //! thing to aim at between the area unlocks. Progress is read off state
    //! the game already keeps, so a contract costs a row in these tables and
    //! nothing else.
    const GOAL_LIFETIME = 0;    //! total cash ever earned
    const GOAL_CREW = 1;        //! bodies on the payroll, all areas
    const GOAL_MACHINE = 2;     //! machine levels, summed
    const GOAL_AREAS = 3;       //! areas opened
    const GOAL_MASTERY = 4;     //! mastery levels, summed
    const GOAL_GEAR = 5;        //! the player's own upgrade levels, summed
    const GOAL_LEGACY = 6;      //! legacy points held

    const GOAL_NAME = [
        "FIND YOUR FEET", "HIRE A HAND", "RAISE A MILL", "LEARN THE TRADE",
        "OPEN THE QUARRY", "A FULL SHIFT", "SEASONED HANDS", "TWO TRADES",
        "OPEN THE MINE", "MASTER OF TWO", "A REAL PAYROLL", "FIVE MILLION",
        "OPEN THE FIELD", "INDUSTRIALIST", "MOVE CAMP", "MASTER OF THE VALLEY",
        "FIVE CAMPS", "A BILLION"
    ];
    const GOAL_KIND = [
        GOAL_GEAR, GOAL_CREW, GOAL_MACHINE, GOAL_MASTERY,
        GOAL_AREAS, GOAL_CREW, GOAL_GEAR, GOAL_MACHINE,
        GOAL_AREAS, GOAL_MASTERY, GOAL_CREW, GOAL_LIFETIME,
        GOAL_AREAS, GOAL_MACHINE, GOAL_LEGACY, GOAL_MASTERY,
        GOAL_LEGACY, GOAL_LIFETIME
    ];
    const GOAL_TARGET = [
        3.0, 1.0, 1.0, 2.0,
        2.0, 6.0, 15.0, 6.0,
        3.0, 10.0, 14.0, 5000000.0,
        4.0, 20.0, 1.0, 30.0,
        5.0, 1000000000.0
    ];
    //! Paid once, on completion. Sized to buy roughly the next thing the
    //! player was already saving for, not to replace playing for it.
    const GOAL_REWARD = [
        60.0, 150.0, 400.0, 900.0,
        1800.0, 4000.0, 9000.0, 22000.0,
        50000.0, 120000.0, 260000.0, 600000.0,
        1400000.0, 3500000.0, 9000000.0, 22000000.0,
        55000000.0, 140000000.0
    ];

    // --- Legacy (moving camp) -------------------------------------------
    //! Walk away from the valley and start it again with what you learned:
    //! cash, upgrades, crews, machines and unlocks all go, mastery and
    //! contracts stay, and every legacy point is a permanent cut of
    //! everything you will ever earn again.
    //! Lifetime, this run, per legacy point squared: the first point lands
    //! at $5M, the second at $20M, the fifth at $125M. Deliberately past the
    //! mine, so nobody is offered a reset before they have seen the game.
    const PRESTIGE_SCALE = 5000000.0;
    const LEGACY_STEP = 0.30;

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
