#include "tc_catch2.h"
#include "../../src/server/game/Loot/QuestCollectionLoot.h"

TEST_CASE("Collection guarantee excludes special loot and preserves group and reference rolls", "[QuestCollectionLoot]")
{
    ItemEntry basic{};
    ItemSparseEntry sparse{};
    ItemTemplate item{};
    item.BasicData = &basic;
    item.ExtendedData = &sparse;
    basic.ClassID = ITEM_CLASS_QUEST;
    sparse.OverallQualityID = ITEM_QUALITY_NORMAL;
    LootStoreItem row(1, LootStoreItem::Type::Item, 20.0f, true, 1, 0, 1, 1);
    REQUIRE(QuestCollectionLoot::IsOrdinary(row, item));
    SECTION("reference") { row.type = LootStoreItem::Type::Reference; }
    SECTION("group") { row.groupid = 1; }
    SECTION("ordinary world drop") { row.needs_quest = false; }
    SECTION("disabled row") { row.chance = 0.0f; }
    SECTION("equipment") { basic.ClassID = ITEM_CLASS_ARMOR; }
    SECTION("rare collectible") { sparse.OverallQualityID = ITEM_QUALITY_RARE; }
    SECTION("quest starter") { sparse.StartQuestID = 123; }
    SECTION("ignore quest status") { item.FlagsCu = ITEM_FLAGS_CU_IGNORE_QUEST_STATUS; }
    SECTION("follow loot rules") { item.FlagsCu = ITEM_FLAGS_CU_FOLLOW_LOOT_RULES; }
    CHECK_FALSE(QuestCollectionLoot::IsOrdinary(row, item));
}

TEST_CASE("Collection guarantee is limited to mandatory item objectives", "[QuestCollectionLoot]")
{
    QuestObjective objective;
    objective.Type = QUEST_OBJECTIVE_ITEM;
    objective.ObjectID = 123;
    objective.Amount = 10;
    REQUIRE(QuestCollectionLoot::IsRequiredItemObjective(objective, 123));
    CHECK_FALSE(QuestCollectionLoot::IsRequiredItemObjective(objective, 456));
    objective.Flags = QUEST_OBJECTIVE_FLAG_OPTIONAL;
    CHECK_FALSE(QuestCollectionLoot::IsRequiredItemObjective(objective, 123));
    objective.Flags = 0;
    objective.Type = QUEST_OBJECTIVE_MONSTER;
    CHECK_FALSE(QuestCollectionLoot::IsRequiredItemObjective(objective, 123));
}
