"""patch_check --hooks: a game patch that renames a hooked function or window
event is reported, not left to go silent in play (2026-10-21)."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import patch_check  # noqa: E402


class CheckHooksTests(unittest.TestCase):
    def setUp(self):
        self.headers = {
            "STVQuestTrackerWidget": "class USTVQuestTrackerWidget { void UpdateQuestLine(FName Id); };",
            "WBP_TechTreeView": "void PostRefreshGrid();\nvoid BP_OnActivated();",
        }

    def test_all_found(self):
        paths = {("/Script/STVoyager.STVQuestTrackerWidget", "UpdateQuestLine"): ["quest.lua"],
                 ("/Game/STVoyager/Tech/UI/WBP_TechTreeView.WBP_TechTreeView_C", "PostRefreshGrid"): ["techtree.lua"]}
        self.assertEqual(patch_check.check_hooks(self.headers, paths, {"BP_OnActivated": ["popups.lua"]}), ([], []))

    def test_renamed_function_and_event_are_problems(self):
        paths = {("/Script/STVoyager.STVQuestTrackerWidget", "UpdateQuestLines"): ["quest.lua"]}
        problems, leads = patch_check.check_hooks(self.headers, paths, {"OnOpenedRenamed": ["popups.lua"]})
        self.assertEqual(len(problems), 2)
        self.assertIn("UpdateQuestLines", problems[0])
        self.assertIn("OnOpenedRenamed", problems[1])
        self.assertEqual(leads, [])

    def test_class_missing_from_dump_is_only_a_lead(self):
        paths = {("/Game/X/WBP_Other.WBP_Other_C", "Foo"): ["a.lua"]}
        problems, leads = patch_check.check_hooks(self.headers, paths, {})
        self.assertEqual(problems, [])
        self.assertEqual(len(leads), 1)

    def test_the_mod_has_hooks_to_check(self):
        paths, events = patch_check.hooks_in_mod()
        self.assertTrue(any(fn == "UpdateQuestLine" for _, fn in paths))
        self.assertIn("BP_OnActivated", events)


if __name__ == "__main__":
    unittest.main()
