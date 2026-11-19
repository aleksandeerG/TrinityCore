-- Local Mighty Caravan Brutosaur for the Forever 70938 client.
-- The client already ships these models, their skins, and their textures.
-- Model attachment 0 is the rider. Attachments 39 and 40 are the side seats.
-- The matching world migration supplies creature 1900058 and its accessories.
START TRANSACTION;

DELETE FROM `creature_model_data` WHERE `ID` IN (19000, 19001) AND `VerifiedBuild` = 70938;
INSERT INTO `creature_model_data`
    (`ID`, `FileDataID`, `WalkSpeed`, `RunSpeed`, `CollisionWidth`, `CollisionHeight`, `MountHeight`,
     `ModelScale`, `AttachedEffectScale`, `WorldEffectScale`, `MountScaleSelf`, `MountScaleOther1`, `MountScaleOther2`, `VerifiedBuild`)
VALUES
    (19000, 1881816, 2.5, 9.7, 4.5, 7.12, 7.11, 1, 1, 1, 1, 1, 1, 70938),
    (19001, 1660381, 2.5, 7,   0.8,  2.2,  0,    1, 1, 1, 1, 1, 1, 70938);

-- Dedicated displays keep other templates that share the old Retail display IDs isolated.
DELETE FROM `creature_display_info` WHERE `ID` IN (180000, 180001, 180002) AND `VerifiedBuild` = 70938;
INSERT INTO `creature_display_info`
    (`ID`, `ModelID`, `CreatureModelScale`, `CreatureModelAlpha`, `PetInstanceScale`,
     `UnarmedWeaponType`, `Unknown_1100_1`, `TextureVariationFileDataID1`, `VerifiedBuild`)
VALUES
    (180000, 19000, 1, 255, 1, -1, 45, 1881958, 70938),
    (180001, 19001, 1, 255, 1, -1, 45, 1660518, 70938),
    (180002, 19001, 1, 255, 1, -1, 45, 1660520, 70938);

-- Apply Aura: Mounted. The mechanics match Forever ground mount spell 436288.
-- Mount type 471 uses Forever's 60% ground capability with no riding skill requirement.
DELETE FROM `spell_name` WHERE `ID` = 1500058 AND `VerifiedBuild` = 70938;
INSERT INTO `spell_name` (`ID`, `Name`, `VerifiedBuild`) VALUES
    (1500058, 'Mighty Caravan Brutosaur', 70938);

DELETE FROM `spell_misc` WHERE `ID` = 1500058 AND `VerifiedBuild` = 70938;
INSERT INTO `spell_misc`
    (`ID`, `Attributes1`, `Attributes9`, `Attributes16`, `CastingTimeIndex`, `DurationIndex`, `RangeIndex`,
     `SchoolMask`, `SpellIconFileDataID`, `ActiveIconFileDataID`, `SpellID`, `VerifiedBuild`)
VALUES
    (1500058, 269582608, 4096, 8192, 14, 21, 1, 1, 132253, 136116, 1500058, 70938);

DELETE FROM `spell_effect` WHERE `ID` = 1500058 AND `VerifiedBuild` = 70938;
INSERT INTO `spell_effect`
    (`ID`, `EffectAura`, `Effect`, `EffectChainAmplitude`, `PvpMultiplier`, `GroupSizeBasePointsCoefficient`,
     `EffectMiscValue1`, `ImplicitTarget1`, `SpellID`, `VerifiedBuild`)
VALUES
    (1500058, 78, 6, 1, 1, 1, 1900058, 1, 1500058, 70938);

DELETE FROM `spell_levels` WHERE `ID` = 1500058 AND `VerifiedBuild` = 70938;
INSERT INTO `spell_levels` (`ID`, `SpellLevel`, `SpellID`, `VerifiedBuild`) VALUES
    (1500058, 0, 1500058, 70938);

DELETE FROM `spell_categories` WHERE `ID` = 1500058 AND `VerifiedBuild` = 70938;
INSERT INTO `spell_categories` (`ID`, `Mechanic`, `SpellID`, `VerifiedBuild`) VALUES
    (1500058, 21, 1500058, 70938);

-- Spell.db2 contains the localized tooltip strings. The worldserver only loads SpellName.db2.
DELETE FROM `hotfix_blob` WHERE `TableHash` = 0xE111669E AND `RecordId` = 1500058 AND `locale` = 'enUS';
INSERT INTO `hotfix_blob` (`TableHash`, `RecordId`, `locale`, `Blob`, `VerifiedBuild`) VALUES
    (0xE111669E, 1500058, 'enUS', CONCAT(0x00, 'Summons and dismisses your Mighty Caravan Brutosaur.', 0x00,
        'Carries a vendor and an auctioneer.', 0x00), 70938);

DELETE FROM `mount` WHERE `ID` = 3950 AND `VerifiedBuild` = 70938;
INSERT INTO `mount` (`ID`, `Name`, `SourceText`, `Description`, `MountTypeID`, `SourceSpellID`, `UiModelSceneID`, `VerifiedBuild`) VALUES
    (3950, 'Mighty Caravan Brutosaur', '', 'A caravan mount with an auctioneer and a repair vendor.', 471, 1500058, 4, 70938);

DELETE FROM `mount_x_display` WHERE `ID` = 9950 AND `VerifiedBuild` = 70938;
INSERT INTO `mount_x_display` (`ID`, `MountID`, `CreatureDisplayInfoID`, `VerifiedBuild`) VALUES
    (9950, 3950, 180000, 70938);

-- Seat flags 0x80000004 allow passengers to be interacted with and disable their gravity.
-- FlagsB 0x2 allows forced boarding by the accessory spell without advertising open seats.
-- The server uses these offsets for passenger world positions. The client has matching
-- attachment points for rendering; check placement and interaction range in game.
DELETE FROM `vehicle_seat` WHERE `ID` IN (30000, 30001) AND `VerifiedBuild` = 70938;
INSERT INTO `vehicle_seat`
    (`ID`, `AttachmentID`, `AttachmentOffsetX`, `AttachmentOffsetY`, `AttachmentOffsetZ`, `Flags`, `FlagsB`, `VerifiedBuild`)
VALUES
    (30000, 39, -0.26,  2.89, 3.58, -2147483644, 2, 70938),
    (30001, 40, -0.20, -2.96, 3.58, -2147483644, 2, 70938);

DELETE FROM `vehicle` WHERE `ID` = 20000 AND `VerifiedBuild` = 70938;
INSERT INTO `vehicle` (`ID`, `SeatID1`, `SeatID2`, `VerifiedBuild`) VALUES
    (20000, 30000, 30001, 70938);

-- Publish each record under a dedicated push ID so clients can cache it independently.
DELETE FROM `hotfix_data` WHERE `Id` BETWEEN 2200058 AND 2200073 AND `UniqueId` = `Id` + 1287800000;
INSERT INTO `hotfix_data` (`Id`, `UniqueId`, `TableHash`, `RecordId`, `Status`, `VerifiedBuild`) VALUES
    (2200058, 1290000058, 0x7F695FA5,   19000, 1, 70938), -- CreatureModelData
    (2200059, 1290000059, 0x7F695FA5,   19001, 1, 70938),
    (2200060, 1290000060, 0xBFDAF9F1,  180000, 1, 70938), -- CreatureDisplayInfo
    (2200061, 1290000061, 0xBFDAF9F1,  180001, 1, 70938),
    (2200062, 1290000062, 0xBFDAF9F1,  180002, 1, 70938),
    (2200063, 1290000063, 0x46C66698, 1500058, 1, 70938), -- SpellName
    (2200064, 1290000064, 0xC603EE28, 1500058, 1, 70938), -- SpellMisc
    (2200065, 1290000065, 0xF04238A5, 1500058, 1, 70938), -- SpellEffect
    (2200066, 1290000066, 0x1DDEC5E6, 1500058, 1, 70938), -- SpellLevels
    (2200067, 1290000067, 0xDBE7F829, 1500058, 1, 70938), -- SpellCategories
    (2200068, 1290000068, 0xE111669E, 1500058, 1, 70938), -- Spell tooltip
    (2200069, 1290000069, 0x96737A41,    3950, 1, 70938), -- Mount
    (2200070, 1290000070, 0x7900AC49,    9950, 1, 70938), -- MountXDisplay
    (2200071, 1290000071, 0xD4A85CEB,   30000, 1, 70938), -- VehicleSeat
    (2200072, 1290000072, 0xD4A85CEB,   30001, 1, 70938),
    (2200073, 1290000073, 0x0A9F6ABF,   20000, 1, 70938); -- Vehicle

COMMIT;
