# Text windows in the game

Every widget class the game had loaded in the first sector of the demo
(316 classes, read from the running game with ForEachUObject on
2026-10-10). More classes may load later (combat, away missions, Q Trials);
rerun the scan there.

Status: "read" means a module speaks it; "read on open" means
popups.lua speaks its text once when it appears (not yet heard in play
unless noted); "not read" means nothing speaks it yet.

## Dialogue (dialogue.lua)

1. WBP_Dialogue_Window (full screen): read, heard.
2. WBP_Dialogue_Window_SideView, parent WBP_Dialogue_Window_Sector (the comm panel over the ship view): read, heard 2026-10-10.
3. WBP_Dialogue_Popup (story cards): read, heard.
4. WBP_Dialogue_Choice_Sector, WBP_Dialogue_Choice_Text, WBP_DialogueChoice_Button_LeftPart: choices, read through button focus; not yet heard.
5. WBP_Dialogue_Consequences, WBP_Dialogue_Requirement: what a choice costs or needs; not read.

## Read on open (popups.lua)

1. Tutorials: WBP_TutorialInfoWidget, WBP_CombatTutorial, WBP_TutorialScreen1 to 10.
2. Toasts and notifications: WBP_Toast_ChoiceHasImpact, WBP_Toast_Error, WBP_Toast_Receive, WBP_Toast_Warning, WBP_SingleNotification_Default, WBP_SingleNotification_Error.
3. Reports and info: WBP_CrewLossInfoWidget, WBP_EnergyLossInfoWidget, WBP_ResearchReport, WBP_MissionInfoWidget, WBP_CommonInfoWidget, WBP_CommonInfoWidget_MissionInfo, WBP_ResearchInfoWidget, WBP_ConstructionInfoWidget, WBP_ConstructionActionReportWidget, WBP_ConstructionActionErrorInfo, WBP_SideMissionFinished, WBP_EndOfGameMissionInfo_01, WBP_EmergencyFoodActivationInfo, WBP_AM_ConfirmStart, WBP_RoomPrompt, WBP_LogEventWidget.
4. Detail views: WBP_POIDetailView, WBP_PlanetDetailView, WBP_ShipDetailView, WBP_StoryDetailView, WBP_ResourceEventDetailView, WBP_GenericLocationDetailView, WBP_AwayMissionDetailView, WBP_AwayMissionEventView, WBP_PoiEventWidget.

## Not read yet, on purpose

1. Always on screen, would speak at every load; better on a key: WBP_QuestTracker, WBP_QuestDisplay, WBP_QuestLineDisplay, WBP_InfoPanel, WBP_Sideview_InfoPanel (and _Action, _Button, _Resource), WBP_OverviewInfoWidget, WBP_NRG_INFO, WBP_ProductionInfo_Container, WBP_Notifications, WBP_NotificationButton.
2. Mouse-hover tooltips: WBP_HappinessHoverTooltip, WBP_MoraleHoverTooltip, WBP_ResourceHoverTooltip, WBP_ModifierList_Tooltip, WBP_ModifierDescriptionDisplay_Tooltip. Need a keyboard way to ask for them.
3. Away mission setup: WBP_AwayMission_* (hero picker, loadout, skills, risk, recommended traits), WBP_ShuttleMissionSetup, WBP_Hero_InfoCard. Read through focus when reached; check then.
4. Combat: WBP_Combat_AttackInfo, WBP_CombatObjectives. Check when reached.
5. WBP_SavegameNotification: probably "Saving"; left out to avoid chatter.
