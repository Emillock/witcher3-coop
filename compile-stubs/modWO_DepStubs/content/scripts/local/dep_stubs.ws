// Compile-only stand-ins for Custom Player Characters and Chill Out declarations that Witcher Online uses,
// inferred from its call sites. Lets Witcher Online's own 5.x errors surface before the real mods are installed.
// Never ship this, and never install it next to the real mods (duplicate classes).

enum ENR_PlayerType
{
	ENR_PlayerUnknown,
	ENR_PlayerGeralt,
	ENR_PlayerCiri,
	ENR_PlayerWitcher,
	ENR_PlayerWitcheress,
	ENR_PlayerSorceress
}

enum ENR_AppearanceSlot
{
	ENR_RSlotHair,
	ENR_RSlotBody,
	ENR_RSlotTorso,
	ENR_RSlotArms,
	ENR_RSlotGloves,
	ENR_RSlotDress,
	ENR_RSlotLegs,
	ENR_RSlotShoes,
	ENR_RSlotMisc
}

enum ENR_MagicAction
{
	ENR_HandFx,
	ENR_Teleport,
	ENR_CounterPush,
	ENR_SpecialLumos,
	ENR_SpecialWeatherChange,
	ENR_LightAbstract,
	ENR_Slash,
	ENR_ThrowAbstract,
	ENR_Lightning,
	ENR_ProjectileWithPrepare,
	ENR_BombExplosion,
	ENR_Rock,
	ENR_RipApart,
	ENR_HeavyAbstract,
	ENR_FastTravelTeleport,
	ENR_SpecialShield,
	ENR_SpecialTornado,
	ENR_SpecialControl,
	ENR_SpecialMeteor,
	ENR_SpecialServant,
	ENR_SpecialLightningFall,
	ENR_SpecialField,
	ENR_SpecialMeteorFall,
	ENR_SpecialPolymorphism,
	ENR_WaterTrap
}

class NR_Map
{
	function getI(key : string) : int { return 0; }
	function getN(key : string) : name { return ''; }
}

class NR_PlayerManager
{
	var m_appearanceTemplates : array< array<string> >;
	var m_appearanceItems : array< array<string> >;
	var m_headNames : array< name >;

	function GetCurrentPlayerType() : ENR_PlayerType { return ENR_PlayerGeralt; }
	function IsPlayerTypeChangeLocked() : bool { return false; }
	function IsRealEquipmentModeEnabled() : bool { return false; }
}

class NR_MagicAction
{
	var drainStaminaOnPerform : bool;

	function RestoreFromSave() {}
	function OnInit() : bool { return true; }
	function OnPrepare() : bool { return true; }
	function OnPerform() : bool { return true; }
}

class NR_MagicSpecialPolymorphism extends NR_MagicAction
{
	var animalType : name;
	var appearanceName : name;
}

class NR_MagicManager
{
	function GetMap(key : name) : NR_Map { return NULL; }
	function SetActionSkillLevel(action : ENR_MagicAction, level : int) {}
	function AddActionScripted(action : NR_MagicAction) {}
}

class NR_RandomGenerator
{
	function next(max : int) : int { return 0; }
}

function NR_GetPlayerManager() : NR_PlayerManager { return NULL; }
function NR_GetMagicManager() : NR_MagicManager { return NULL; }
function NR_GetRandomGenerator() : NR_RandomGenerator { return NULL; }
function NR_IsSceneInPreviewState() : bool { return false; }

enum EChillSpotType
{
	CST_Chair,
	CST_Table,
	CST_Bench
}

struct SChillSpot
{
	var position : Vector;
	var rotation : EulerAngles;
	var type : EChillSpotType;
}

function ChillSpot(position : Vector, rotation : EulerAngles, type : EChillSpotType) : SChillSpot
{
	var spot : SChillSpot;

	spot.position = position;
	spot.rotation = rotation;
	spot.type = type;
	return spot;
}

class CO_SpotEntGroup
{
	var tag : name;

	function Add(spot : SChillSpot) {}
}

statemachine class ChillOut
{
	var m_groups : array<CO_SpotEntGroup>;

	function InitGroups() {}
	function State() : CScriptableState { return GetCurrentState(); }
}

state CO_Action in ChillOut
{
	function GetAnimation() : name { return ''; }
}

function Chill() : ChillOut { return NULL; }
function CO_CurrentArea() : EAreaName { return AN_Undefined; }
