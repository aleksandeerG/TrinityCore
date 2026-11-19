START TRANSACTION;

-- Use the Brutosaur's own mounted aura for the bonus. The server uses the
-- largest mounted speed modifier, so this overrides the base +60% capability.
DELETE FROM `spell_effect`
WHERE `ID` = 1500059 AND `SpellID` = 1500058 AND `EffectIndex` = 1 AND `VerifiedBuild` = 70938;
INSERT INTO `spell_effect`
    (`ID`, `EffectAura`, `EffectIndex`, `Effect`, `EffectChainAmplitude`, `PvpMultiplier`,
     `GroupSizeBasePointsCoefficient`, `EffectBasePoints`, `ImplicitTarget1`, `SpellID`, `VerifiedBuild`)
VALUES
    (1500059, 32, 1, 6, 1, 1, 1, 200, 1, 1500058, 70938);

DELETE FROM `hotfix_data`
WHERE `Id` = 2200074 AND `UniqueId` = 1290000074 AND `TableHash` = 0xF04238A5 AND `RecordId` = 1500059;
INSERT INTO `hotfix_data` (`Id`, `UniqueId`, `TableHash`, `RecordId`, `Status`, `VerifiedBuild`)
VALUES (2200074, 1290000074, 0xF04238A5, 1500059, 1, 70938);

COMMIT;
