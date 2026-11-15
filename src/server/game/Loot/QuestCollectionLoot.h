// Local optional collection policy. No loot rows or quantities are changed.
#ifndef TRINITY_QUEST_COLLECTION_LOOT_H
#define TRINITY_QUEST_COLLECTION_LOOT_H

#include "ItemTemplate.h"
#include "LootMgr.h"
#include "QuestDef.h"

namespace QuestCollectionLoot
{
inline bool IsOrdinary(LootStoreItem const& row, ItemTemplate const& item)
{
    return row.type == LootStoreItem::Type::Item && row.needs_quest && !row.groupid && row.chance > 0.0f
        && item.GetClass() == ITEM_CLASS_QUEST && item.GetQuality() <= ITEM_QUALITY_NORMAL
        && item.GetInventoryType() == INVTYPE_NON_EQUIP && !item.GetStartQuest()
        && !item.HasFlag(ITEM_FLAGS_CU_IGNORE_QUEST_STATUS) && !item.HasFlag(ITEM_FLAGS_CU_FOLLOW_LOOT_RULES);
}

inline bool IsRequiredItemObjective(QuestObjective const& objective, uint32 itemId)
{
    return objective.Type == QUEST_OBJECTIVE_ITEM && objective.ObjectID == int32(itemId) && objective.Amount > 0
        && !(objective.Flags & QUEST_OBJECTIVE_FLAG_OPTIONAL);
}
}
#endif
