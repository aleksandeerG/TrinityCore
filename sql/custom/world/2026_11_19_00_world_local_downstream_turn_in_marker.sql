START TRANSACTION;

-- Downstream already ends at Ormin Pelford. Add the missing map point using
-- his Eastvale spawn, while preserving existing objective markers.
SET @DownstreamPoiIndex = GREATEST(
    COALESCE((SELECT MAX(`Idx1`) FROM `quest_poi` WHERE `QuestID` = 91733), -1),
    COALESCE((SELECT MAX(`Idx1`) FROM `quest_poi_points` WHERE `QuestID` = 91733), -1)
) + 1;

INSERT INTO `quest_poi` (`QuestID`, `BlobIndex`, `Idx1`, `ObjectiveIndex`, `MapID`, `UiMapID`, `Flags`)
SELECT 91733, 0, @DownstreamPoiIndex, -1, c.`map`, 1429, 1
FROM `creature` c
JOIN `creature_questender` e ON e.`id` = c.`id` AND e.`quest` = 91733
JOIN `quest_template` q ON q.`ID` = e.`quest`
WHERE c.`guid` = 24826500 AND c.`id` = 248265 AND c.`map` = 0
  AND NOT EXISTS (
    SELECT 1 FROM `quest_poi` p
    JOIN `quest_poi_points` pp ON pp.`QuestID` = p.`QuestID` AND pp.`Idx1` = p.`Idx1`
    WHERE p.`QuestID` = 91733 AND p.`ObjectiveIndex` = -1
  );
SET @DownstreamPoiInserted = ROW_COUNT();

INSERT INTO `quest_poi_points` (`QuestID`, `Idx1`, `Idx2`, `X`, `Y`, `Z`)
SELECT 91733, @DownstreamPoiIndex, 0, ROUND(`position_x`), ROUND(`position_y`), ROUND(`position_z`)
FROM `creature`
WHERE `guid` = 24826500 AND @DownstreamPoiInserted = 1;

COMMIT;
