START TRANSACTION;

-- Match the vehicle mode used by player-mounted passenger mounts such as the Yak and Mammoth.
UPDATE `vehicle`
SET `Flags` = 1073741824
WHERE `ID` = 20000 AND `SeatID1` = 30000 AND `SeatID2` = 30001 AND `VerifiedBuild` = 70938;

-- VehicleSeat attachment slots 13 and 14 map to the model's basket anchors 39 and 40.
-- Those anchors already supply the position. The seat offsets are relative to them.
UPDATE `vehicle_seat`
SET `AttachmentID` = CASE `ID` WHEN 30000 THEN 13 ELSE 14 END,
    `AttachmentOffsetX` = 0, `AttachmentOffsetY` = 0, `AttachmentOffsetZ` = 0,
    `PassengerAttachmentID` = -1,
    `RideAnimStart` = -1, `RideAnimLoop` = 91, `RideUpperAnimStart` = -1,
    `Flags` = -2147483642 -- 0x80000006: interaction, no gravity, and lower-body ride animation
WHERE `ID` IN (30000, 30001) AND `VerifiedBuild` = 70938;

COMMIT;
