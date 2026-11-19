-- The mount is granted by learning spell 1500058 after validating it in game.
-- The matching hotfix defines the mount, vehicle 20000, and all three displays.
START TRANSACTION;

DELETE FROM `creature_template` WHERE `entry` = 1900058;
INSERT INTO `creature_template`
    (`entry`, `name`, `faction`, `unit_class`, `type`, `BaseAttackTime`, `RangeAttackTime`, `VehicleId`, `VerifiedBuild`)
VALUES
    (1900058, 'Mighty Caravan Brutosaur', 35, 1, 1, 2000, 2000, 20000, 70938);

DELETE FROM `creature_template_difficulty` WHERE `Entry` = 1900058 AND `DifficultyID` = 0;
INSERT INTO `creature_template_difficulty` (`Entry`, `DifficultyID`, `VerifiedBuild`) VALUES
    (1900058, 0, 70938);

DELETE FROM `creature_template_model` WHERE `CreatureID` IN (1900058, 142666, 142668) AND `Idx` = 0;
INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`) VALUES
    (1900058, 0, 180000, 1,   1, 70938),
    (142666,  0, 180001, 0.8, 1, 70938),
    (142668,  0, 180002, 0.8, 1, 70938);

-- Template model loading also requires world-side radius and reach.
DELETE FROM `creature_model_info` WHERE `DisplayID` IN (180000, 180001, 180002) AND `VerifiedBuild` = 70938;
INSERT INTO `creature_model_info` (`DisplayID`, `BoundingRadius`, `CombatReach`, `VerifiedBuild`) VALUES
    (180000, 4.5,     3,   70938),
    (180001, 1.14061, 1.5, 70938),
    (180002, 1.14061, 1.5, 70938);

-- The loader requires a spell-click row even when accessories specify RideSpellID.
DELETE FROM `npc_spellclick_spells` WHERE `npc_entry` = 1900058 AND `spell_id` = 46598;
INSERT INTO `npc_spellclick_spells` (`npc_entry`, `spell_id`, `cast_flags`, `user_type`) VALUES
    (1900058, 46598, 1, 0);

DELETE FROM `vehicle_template_accessory` WHERE `entry` = 1900058 AND `seat_id` IN (0, 1);
INSERT INTO `vehicle_template_accessory`
    (`entry`, `accessory_entry`, `seat_id`, `minion`, `description`, `summontype`, `summontimer`, `RideSpellID`)
VALUES
    (1900058, 142666, 0, 1, 'Mighty Caravan Brutosaur - Collector Unta', 6, 0, 46598),
    (1900058, 142668, 1, 1, 'Mighty Caravan Brutosaur - Merchant Maku',  6, 0, 46598);

-- Merchant Maku already has the vendor and repair flags. Stock uses normal Classic items.
DELETE FROM `npc_vendor` WHERE `entry` = 142668 AND `item` IN (117, 159, 4540) AND `ExtendedCost` = 0 AND `type` = 1;
INSERT INTO `npc_vendor` (`entry`, `slot`, `item`, `VerifiedBuild`) VALUES
    (142668, 0, 159,  70938), -- Refreshing Spring Water
    (142668, 1, 117,  70938), -- Tough Jerky
    (142668, 2, 4540, 70938); -- Tough Hunk of Bread

COMMIT;
