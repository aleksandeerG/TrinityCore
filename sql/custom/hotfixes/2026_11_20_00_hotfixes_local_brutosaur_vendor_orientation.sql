START TRANSACTION;

-- BrontosaurusMount basket anchors 39 and 40 face outward and tip the
-- passenger's up axis forward. Counter-roll around each seat's own forward
-- axis to keep the vendors upright in their respective baskets.
UPDATE `vehicle_seat`
SET `PassengerRoll` = CASE `AttachmentID` WHEN 13 THEN 1.57079633 ELSE -1.57079633 END
WHERE ((`ID` = 30000 AND `AttachmentID` = 13) OR (`ID` = 30001 AND `AttachmentID` = 14))
  AND `VerifiedBuild` = 70938;

-- Publish fresh push IDs so clients with the previous seat data fetch the update.
DELETE FROM `hotfix_data`
WHERE `TableHash` = 0xD4A85CEB
  AND (`Id`, `UniqueId`, `RecordId`) IN ((2200079, 1290000079, 30000), (2200080, 1290000080, 30001));

INSERT INTO `hotfix_data` (`Id`, `UniqueId`, `TableHash`, `RecordId`, `Status`, `VerifiedBuild`)
VALUES (2200079, 1290000079, 0xD4A85CEB, 30000, 1, 70938),
       (2200080, 1290000080, 0xD4A85CEB, 30001, 1, 70938);

COMMIT;
