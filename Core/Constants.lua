-- VoidcoreAdvisor: Constants
-- All shared constants for the addon. Loaded first so every subsequent file can reference them.
local addonName, VCA = ...

VCA.ADDON_NAME = addonName
VCA.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("VoidcoreAdvisorReborn", "Version")) or "2.11.2"
VCA.SCHEMA_VERSION = 2
VCA.CHAR_DB_NAME = "VoidcoreAdvisorCharDB"
VCA.GLOBAL_DB_NAME = "VoidcoreAdvisorDB"

-- ── Content types ─────────────────────────────────────────────────────────────
-- RAID:        A single raid boss encounter.  Uses encounterID as sourceID.
-- MYTHIC_PLUS: An entire M+ dungeon.          Uses EJ instanceID as sourceID.
VCA.ContentType = {
    RAID = "RAID",
    MYTHIC_PLUS = "MYTHIC_PLUS"
}

-- ── Nebulous Voidcore costs ───────────────────────────────────────────────────
VCA.VoidcoreCost = {
    -- Fallback only: the bonus roll prompt reports the real cost (currencyCost) and the
    -- roll window uses that when it is available.
    RAID = 1,
    MYTHIC_PLUS = 1
}

-- ── Encounter Journal difficulty IDs ─────────────────────────────────────────
VCA.Difficulty = {
    RAID_LFR = 17, -- not eligible for Voidcores
    RAID_NORMAL = 14,
    RAID_HEROIC = 15,
    RAID_MYTHIC = 16,
    DUNGEON_NORMAL = 1,
    DUNGEON_HEROIC = 2,
    DUNGEON_MYTHIC = 23 -- covers both Mythic and Mythic+ in the EJ
}

-- Raid difficulties that are eligible for Nebulous Voidcores.
VCA.EligibleRaidDifficulties = {
    [VCA.Difficulty.RAID_NORMAL] = true,
    [VCA.Difficulty.RAID_HEROIC] = true,
    [VCA.Difficulty.RAID_MYTHIC] = true
}

-- The EJ difficulty used when reading M+ dungeon loot pools.
VCA.MythicPlusEJDifficulty = VCA.Difficulty.DUNGEON_MYTHIC

-- ── M+ tooltip bonus IDs (Myth 1/6 — Voidcore reward tier) ──────────────────
-- These IDs are injected into item links so tooltips render at the correct
-- item level for Nebulous Voidcore rewards from M+ dungeons.
VCA.MythicPlusBonusIDs = {13440, 6652, 12699} -- shared M+ base bonus IDs
VCA.VoidcoreTrackBonusID = 12849 -- Myth 1/6 track

-- ── Raid Voidcore tooltip settings per difficulty ───────────────────────────────
-- ctx = item link context field (5=Hero tier, 6=Myth tier); drives the track label.
-- Track bonus IDs: Veteran 12825-12830, Champion 12833-12838, Hero 12841-12846, Myth 12849-12854.
VCA.RaidVoidcoreTooltip = {
    [VCA.Difficulty.RAID_NORMAL] = {
        ctx = "5",
        bonus = 12841, -- Hero 1/6
        tag = 13334 -- Heroic difficulty tag
    },
    [VCA.Difficulty.RAID_HEROIC] = {
        ctx = "6",
        bonus = 12849, -- Myth 1/6
        tag = 13335 -- Mythic difficulty tag
    },
    [VCA.Difficulty.RAID_MYTHIC] = {
        ctx = "6",
        bonus = 12854, -- Myth 6/6
        tag = 13335 -- Mythic difficulty tag
    }
}

-- Items that need an extra bonus ID (13708) in the Heroic link; raw EJ link on Mythic.
VCA.RaidTooltipExtraBonusItems = {
    [268265] = true,
    [271875] = true,
    [271878] = true -- Ula'tek plate legs (Unbound Rancor)
}

-- Items excluded from specific encounters (do not drop from Voidcores).
VCA.LootPoolExclusions = {
    [2895] = {
        [270909] = true
    } -- Ula'tek
}

-- Per-encounter bonus ID overrides for specific difficulties.
VCA.RaidEncounterTooltipBonus = {
    [VCA.Difficulty.RAID_MYTHIC] = {
        [2883] = {"13335", "13708", "13848"}, -- The Coiled Altar
        [2895] = {"13335", "13708", "13848"} -- Ula'tek
    }
}

-- ── M+ Great Vault reward data ────────────────────────────────────────────────
-- Maps each key level to its Great Vault reward upgrade track.
-- Track bonus IDs: Veteran 12825-12830, Champion 12833-12838, Hero 12841-12846, Myth 12849-12854.
VCA.MythicPlusVaultRewards = {
    [2] = {
        track = "Hero 1/6",
        bonusID = 12841
    },
    [3] = {
        track = "Hero 1/6",
        bonusID = 12841
    },
    [4] = {
        track = "Hero 2/6",
        bonusID = 12842
    },
    [5] = {
        track = "Hero 2/6",
        bonusID = 12842
    },
    [6] = {
        track = "Hero 3/6",
        bonusID = 12843
    },
    [7] = {
        track = "Hero 4/6",
        bonusID = 12844
    },
    [8] = {
        track = "Hero 4/6",
        bonusID = 12844
    },
    [9] = {
        track = "Hero 4/6",
        bonusID = 12844
    },
    [10] = {
        track = "Myth 1/6",
        bonusID = 12849
    }
}
-- ── Nebulous Voidcore currency ─────────────────────────────────────────────
VCA.VOIDCORE_CURRENCY_ID = 3418 -- Nebulous Voidcore (Season 1)
-- ── Nebulous Voidcache item IDs ───────────────────────────────────────────────
-- Maps current-season M+ dungeon EJ instanceID → its Nebulous Voidcache item ID.
-- Used by VoidcacheScan to read per-spec loot lists from the Voidcache tooltip.
-- instanceIDs from /vcagen list
VCA.DungeonVoidcacheIDs = {
    -- Season 1 (12.0.x)
    -- [1201] = 268465, -- Algeth'ar Academy
    -- [1300] = 268466, -- Magisters' Terrace
    -- [1316] = 268467, -- Nexus-Point Xenas
    -- [278] = 268468, -- Pit of Saron
    -- [945] = 268469, -- Seat of the Triumvirate
    -- [476] = 268470, -- Skyreach
    -- [1299] = 268471, -- Windrunner Spire
    -- [1315] = 268473, -- Maisara Caverns
    -- Season 2 (12.1.0)
    [1322] = 279618, -- Altar of Fangs
    [1311] = 279620, -- Den of Nalorakk
    [1304] = 279623, -- Murder Row
    [1309] = 279619, -- The Blinding Vale
    [1313] = 279625, -- Voidscar Arena
    [1041] = 279621, -- Kings' Rest
    [1202] = 279622, -- Ruby Life Pools
    [1030] = 279624 -- Temple of Sethraliss
}

-- ── Raid Nebulous Voidcache item IDs ─────────────────────────────────────────
-- Maps current-season raid encounterID → its Nebulous Voidcache item ID.
-- Only encounters that award Voidcaches are listed here.
-- encounterIDs from /vcagen list; voidcache item names may differ from encounter
-- names (e.g. "Tortollan Explorers" vs "The Lost Explorers") — mapped manually.
VCA.RaidEncounterCacheIDs = {
    -- Season 1 (12.0.x) — Crown of Midnight
    -- [2733] = 268459, -- Imperator Averzian
    -- [2734] = 268460, -- Vorasius
    -- [2735] = 268462, -- Vaelgor & Ezzorak
    -- [2736] = 268461, -- Fallen-King Salhadaar
    -- [2737] = 268463, -- Lightblinded Vanguard
    -- [2738] = 267488, -- Crown of the Cosmos
    -- [2739] = 268458, -- Belo'ren, Child of Al'ar
    -- [2740] = 262658, -- Midnight Falls
    -- [2795] = 268464, -- Chimaerus the Undreamt God
    -- [2711] = 275228, -- Rotmire
    -- Season 2 (12.1.0) — The Tidebound Grotto (instanceID 1317)
    [2849] = 274708, -- Nymrissa Wavecaller
    -- Season 2 (12.1.0) — The Venomous Abyss (instanceID 1320)
    [2888] = 278285, -- Nek'zali the Soulcoiler  (item: Soulcoiler Nek'zali)
    [2874] = 278283, -- Entombed Sentinels
    [2894] = 278286, -- The Lost Explorers       (item: Tortollan Explorers)
    [2882] = 278287, -- Vashnik the Malignant    (item: Vashnik)
    [2871] = 278288, -- Sszorak
    [2887] = 278289, -- The Twin Fangs
    [2883] = 278290, -- The Coiled Altar
    [2895] = 278284 -- Ula'tek
}

-- ── Detection ─────────────────────────────────────────────────────────────────
-- How long (seconds) after a successful encounter the addon watches for loot
-- appearing in bags from a Voidcore bonus prompt.
VCA.DETECTION_WINDOW_SECONDS = 45
