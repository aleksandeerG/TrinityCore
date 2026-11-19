START TRANSACTION;

-- Many Forever areas allow ground mounts but have neither swimming mount flag.
-- Keep ground capability 555 and add a water-only capability with the restriction
-- override (0x20), surface (0x04), underwater (0x08), and the usual 0x10 flag.
DELETE FROM `mount_capability` WHERE `ID` = 19000 AND `VerifiedBuild` = 70938;
INSERT INTO `mount_capability` (`ID`, `Flags`, `ModSpellAuraID`, `ReqMapID`, `VerifiedBuild`)
VALUES (19000, 60, 86457, -1, 70938);

DELETE FROM `mount_type_x_capability` WHERE `ID` IN (20001, 20002) AND `MountTypeID` = 20001 AND `VerifiedBuild` = 70938;
INSERT INTO `mount_type_x_capability` (`ID`, `MountTypeID`, `MountCapabilityID`, `OrderIndex`, `VerifiedBuild`)
VALUES (20001, 20001, 555, 0, 70938),
       (20002, 20001, 19000, 1, 70938);

-- MountType.db2 is client-only. Its 70938 payload contains the 32-bit ground type
-- followed by 24 little-endian 32-bit capability IDs. Only the first two are used.
DELETE FROM `hotfix_blob` WHERE `TableHash` = 0xC5B875A8 AND `RecordId` = 20001 AND `locale` = 'enUS';
INSERT INTO `hotfix_blob` (`TableHash`, `RecordId`, `locale`, `Blob`, `VerifiedBuild`)
VALUES (0xC5B875A8, 20001, 'enUS', CONCAT(0x000000002B020000384A0000, UNHEX(REPEAT('00', 88))), 70938);

DELETE FROM `hotfix_data` WHERE `Id` BETWEEN 2200075 AND 2200078 AND `UniqueId` = `Id` + 1287800000;
INSERT INTO `hotfix_data` (`Id`, `UniqueId`, `TableHash`, `RecordId`, `Status`, `VerifiedBuild`) VALUES
    (2200075, 1290000075, 0xF66E0076, 19000, 1, 70938), -- MountCapability
    (2200076, 1290000076, 0x28D9DEA9, 20001, 1, 70938), -- MountTypeXCapability
    (2200077, 1290000077, 0x28D9DEA9, 20002, 1, 70938), -- MountTypeXCapability
    (2200078, 1290000078, 0xC5B875A8, 20001, 1, 70938); -- MountType

UPDATE `mount`
SET `MountTypeID` = 20001
WHERE `ID` = 3950 AND `SourceSpellID` = 1500058 AND `MountTypeID` = 471 AND `VerifiedBuild` = 70938;

COMMIT;
