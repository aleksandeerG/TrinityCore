START TRANSACTION;

-- Retail display 83632 uses scale 0.75 with the same model (FileDataID 1881816).
UPDATE `creature_display_info`
SET `CreatureModelScale` = 0.75
WHERE `ID` = 180000 AND `ModelID` = 19000 AND `VerifiedBuild` = 70938;

-- World-space boarding offsets use the model's side attachments at the new scale.
-- Both vendors share a Tortollan model that supports mount animation 91.
UPDATE `vehicle_seat`
SET `AttachmentOffsetX` = -0.19532, `AttachmentOffsetY` = 2.16692, `AttachmentOffsetZ` = 2.68163,
    `RideAnimStart` = 91, `RideAnimLoop` = 91
WHERE `ID` = 30000 AND `AttachmentID` = 39 AND `VerifiedBuild` = 70938;

UPDATE `vehicle_seat`
SET `AttachmentOffsetX` = -0.14651, `AttachmentOffsetY` = -2.21927, `AttachmentOffsetZ` = 2.68497,
    `RideAnimStart` = 91, `RideAnimLoop` = 91
WHERE `ID` = 30001 AND `AttachmentID` = 40 AND `VerifiedBuild` = 70938;

COMMIT;
