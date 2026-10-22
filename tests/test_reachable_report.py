"""reachable_report: the widget class graph, its roots, and what counts as read
(2026-10-21). Small made-up inputs; the one check on the real exports skips when
they are not on this machine."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
try:
    import reachable_report as rr  # noqa: E402
except ImportError:   # the public copy leaves the local report tools out
    rr = None


def tree(asset, super_="UserWidget", widgets=(), spawns=()):
    return {"asset": asset, "class": asset.rsplit("/", 1)[-1] + "_C", "super": super_, "root": None,
            "widgets": [{"name": n, "class": c, "parent": None, "texts": [{"prop": "Text", "text": t} for t in tx]}
                        for n, c, tx in widgets],
            "spawns": list(spawns)}


@unittest.skipIf(rr is None, "tools/reachable_report.py is not in this copy")
class GraphTests(unittest.TestCase):
    def setUp(self):
        self.trees = {
            "WBP_HUD": tree("/Game/STVoyager/GeneralUI/WBP_HUD",
                            widgets=[("Bar", "WBP_Bar_C", []), ("Title", "TextBlock", ["Sector"])]),
            "WBP_Bar": tree("/Game/STVoyager/GeneralUI/WBP_Bar", spawns=["WBP_BarEntry"]),
            "WBP_BarEntry": tree("/Game/STVoyager/GeneralUI/WBP_BarEntry"),
            "WBP_Lonely": tree("/Game/STVoyager/Events/WBP_Lonely", widgets=[("T", "TextBlock", ["Hello there"])]),
            "WBP_Room": tree("/Game/STVoyager/ConstructionSideview/WBP_Room"),
            "WBP_PowerModule": tree("/Game/STVoyager/ConstructionSideview/WBP_PowerModule"),
            "WBP_Popup": tree("/Game/STVoyager/LibUI/WBP_Popup"),
        }

    def statuses(self, refs=None, lua=(), headers=None):
        reached, roots, status, unreachable = rr.build(self.trees, headers or {}, refs, list(lua))
        return reached, roots, status, unreachable

    def test_containment_and_spawns_are_inside_a_read_hud(self):
        _, _, status, _ = self.statuses(refs=[], lua=['FindAllOf("WBP_HUD_C")'])
        self.assertEqual(status["WBP_HUD"], "read")
        self.assertEqual(status["WBP_Bar"], "inside")
        self.assertEqual(status["WBP_BarEntry"], "inside")

    def test_without_the_read_hud_its_children_are_not_named(self):
        _, _, status, _ = self.statuses(refs=[], lua=[])
        self.assertEqual(status["WBP_Bar"], "not named")

    def test_with_refs_an_unreferenced_class_is_unreachable(self):
        _, _, status, unreachable = self.statuses(refs=[])
        self.assertIn("WBP_Lonely", unreachable)
        self.assertNotIn("WBP_Lonely", status)

    def test_without_refs_every_orphan_is_a_root(self):
        _, roots, status, unreachable = self.statuses(refs=None)
        self.assertIn("WBP_Lonely", roots)
        self.assertIn("WBP_Lonely", status)
        self.assertEqual(unreachable, [])

    def test_a_data_asset_reference_makes_a_root(self):
        refs = ["STVoyager/Content/STVoyager/Events/DA_EventConfig.uasset\timport\tWBP_Lonely"]
        _, roots, status, _ = self.statuses(refs=refs)
        self.assertEqual(roots["WBP_Lonely"], "DA_EventConfig")
        self.assertEqual(status["WBP_Lonely"], "not named")

    def test_config_hosted_modules_are_inside_the_read_room_window(self):
        ini = "STVoyager/Config/DefaultGame.ini [/Script/STVoyager.STVUISettings] "
        refs = [ini + "RoomManagementMenuPtr\tconfig\tWBP_Room", ini + "RoomInteractUIModules\tconfig\tWBP_PowerModule"]
        _, roots, status, _ = self.statuses(refs=refs, lua=['"WBP_Room_C"'])
        self.assertEqual(roots["WBP_PowerModule"], "DefaultGame.ini STVUISettings RoomInteractUIModules")
        self.assertEqual(status["WBP_PowerModule"], "inside")
        # The negative twin: the same module under another key is its own window.
        refs[1] = ini + "PopUpMenuClass\tconfig\tWBP_PowerModule"
        _, _, status, _ = self.statuses(refs=refs, lua=['"WBP_Room_C"'])
        self.assertEqual(status["WBP_PowerModule"], "not named")

    def test_a_soft_reference_from_a_read_window_is_near(self):
        refs = ["STVoyager/Content/STVoyager/LibUI/WBP_Popup.uasset\tname\tWBP_Lonely",
                "STVoyager/Content/Blueprints/BP_PlayerController.uasset\timport\tWBP_Popup"]
        _, _, status, _ = self.statuses(refs=refs, lua=['"WBP_Popup_C"'])
        self.assertEqual(status["WBP_Lonely"], "near")

    def test_a_header_naming_a_class_is_a_code_edge(self):
        headers = {"WBP_HUD": "class UWBP_HUD_C { class UWBP_Popup_C* Popup; };"}
        reached, _, _, unreachable = self.statuses(refs=[], headers=headers)
        self.assertEqual(reached["WBP_Popup"], ("WBP_HUD", "code"))
        _, _, _, unreachable = self.statuses(refs=[])
        self.assertIn("WBP_Popup", unreachable)

    def test_lua_prefixes_and_instance_names(self):
        exact, prefixes, _ = rr.mod_names(['x = "WBP_HUD_C_123"', 'if p:find("WBP_TUT_") then', '"WBP_Bar_C"'])
        self.assertEqual(exact, {"WBP_HUD", "WBP_Bar"})
        self.assertEqual(prefixes, {"WBP_TUT_"})
        # A name that is no class but starts some is a prefix too.
        _, _, status, _ = self.statuses(refs=[], lua=['find("WBP_BarE")'])
        self.assertEqual(status["WBP_BarEntry"], "read")
        self.assertEqual(status["WBP_Bar"], "not named")

    def test_native_base_named_in_lua_counts_as_read(self):
        self.trees["WBP_Plaque"] = tree("/Game/STVoyager/Events/WBP_Plaque", super_="STVHeroPlaque")
        self.trees["WBP_HUD"]["widgets"].append({"name": "P", "class": "WBP_Plaque_C", "parent": None, "texts": []})
        _, _, status, _ = self.statuses(refs=[], lua=['IsA("STVHeroPlaque")'])
        self.assertEqual(status["WBP_Plaque"], "read")
        _, _, status, _ = self.statuses(refs=[], lua=[])
        self.assertEqual(status["WBP_Plaque"], "not named")

    def test_texts_and_areas_are_short(self):
        self.assertEqual(rr.short_text("<b>Select</b> a Resource Type to store in this bay"), "Select a Resource Type to...")
        self.assertEqual(rr.short_text("Confirm"), "Confirm")
        self.assertEqual(rr.area("/Game/STVoyager/Events/UI/WBP_X"), "Events")
        self.assertEqual(rr.area("/Game/CombatPrototype/Blueprints/WBP_Y"), "CombatPrototype")
        self.assertEqual(rr.own_texts(self.trees["WBP_HUD"]), ["Sector"])


@unittest.skipIf(rr is None or not (ROOT / "dumps" / "widgets").is_dir(), "no widget exports on this machine")
class RealExportsTests(unittest.TestCase):
    def test_hud_and_main_menu_are_reachable(self):
        trees = rr.load_trees(ROOT / "dumps" / "widgets")
        refs = ROOT / "dumps" / "widget-refs.txt"
        lines = refs.read_text(encoding="utf-8").splitlines() if refs.exists() else None
        reached, _, status, _ = rr.build(trees, {}, lines, [])
        self.assertIn("WBP_HUD", reached)
        self.assertIn("WBP_MainMenu", reached)
        self.assertGreater(len(status), 100)


if __name__ == "__main__":
    unittest.main()
