-- Local fallback for Temple Highguard displays 147839, 147840, 147841
-- and Iron Kingsguard displays 147966, 147968, 147971.
-- After an upstream merge, check these IDs for official rows before
-- retaining the fallback. Later INSERT IGNORE statements keep existing rows.
--
-- Radius/reach from displays on the exact same client models:
-- 147834 (Temple Highguard, model 7300), 147965 (Iron Kingsguard, model 5408),
-- and 1608 (Ironforge Mountaineer, model 7203).
INSERT IGNORE INTO `creature_model_info` (`DisplayID`, `BoundingRadius`, `CombatReach`, `DisplayID_Other_Gender`, `VerifiedBuild`) VALUES
(147839, 0.306, 1.5, 0, 0),
(147840, 0.306, 1.5, 0, 0),
(147841, 0.306, 1.5, 0, 0),
(147966, 0.347, 1.5, 0, 0),
(147968, 0.347, 1.5, 0, 0),
(147971, 0.347, 1.5, 0, 0);
