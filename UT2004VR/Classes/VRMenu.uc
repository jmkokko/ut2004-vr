//=============================================================================
// VRMenu: UT's menus as a panel in the headset, shared by the player controller (in a game) and VRConsole (the
// main menus, where no VR controller exists). It tells the proxy whether a menu is up ("P"), where UT's menu
// cursor is ("Q", it isn't in the captured image) and the active page's bounds ("R", so the panel is cropped to
// the page); moves the cursor to the controller's pointer ("U" from the proxy); and makes the trigger act as UT's
// left mouse button: press -> OnMousePressed, drag (sliders, scrollbars) -> OnCapturedMouseMove, release ->
// OnMouseRelease, then OnClick if still over the control (injected Windows mouse clicks never reached UT's menu).
//=============================================================================
class VRMenu extends Object;

var bool  bOpen;                 // a menu (GUI) is up
var bool  bOldTrigger;
var GUIComponent PressedCtl;     // control under the pointer when the trigger went down (gets drags, release, click)
var float LastX, LastY;
var float NextMsg;

static function float WinW(GUIController G) { return float(G.ResX); }
static function float WinH(GUIController G) { return float(G.ResY); }

// once per tick. ViewMode tells the proxy what the headset shows ("M"): 0 a VR game renders the eyes, 1 the main
// menus (the proxy's dark room with the menu panel), 2 a game without VR (the window on a big screen); -1 nothing yet
function Update(VRLink Link, GUIController G, bool bKeyboardMouse, bool bTrigger, float Now, int ViewMode)
{
	local bool bUp;
	if ( Link == None )
		return;
	bUp = G != None && G.bActive;
	if ( bUp != bOpen || Now > NextMsg || NextMsg - Now > 2 )
	{
		bOpen = bUp;
		NextMsg = Now + 0.5;
		if ( !bUp )
			Link.ToProxy("P 0");
		else if ( bKeyboardMouse )
			Link.ToProxy("P 1 k");
		else
			Link.ToProxy("P 1 c");
		if ( ViewMode >= 0 )
			Link.ToProxy("M " $ ViewMode);
	}
	// controller mode: the trigger is the mouse button
	if ( bUp && !bKeyboardMouse )
	{
		if ( bTrigger && !bOldTrigger )
			Press(G);
		else if ( bTrigger )
			Held(G);
		else if ( bOldTrigger )
			Release();
	}
	else
		PressedCtl = None;
	bOldTrigger = bTrigger;
	if ( bUp && G.ResX > 0 && G.ResY > 0 )
	{
		Link.ToProxy("Q " $ (G.MouseX / WinW(G)) $ " " $ (G.MouseY / WinH(G)));
		if ( G.ActivePage != None && G.ActivePage.ActualWidth() > 16 && G.ActivePage.ActualHeight() > 16 )
			Link.ToProxy("R " $ (G.ActivePage.ActualLeft() / WinW(G)) $ " " $ (G.ActivePage.ActualTop() / WinH(G)) $ " "
				$ (G.ActivePage.ActualWidth() / WinW(G)) $ " " $ (G.ActivePage.ActualHeight() / WinH(G)));
	}
}

// the controller's pointer on the panel (window uv 0..1, from the proxy's "U")
function Pointer(GUIController G, float U, float V, bool bKeyboardMouse)
{
	if ( !bOpen || bKeyboardMouse || G == None || G.ResX <= 0 )
		return;
	G.MouseX = U * WinW(G);
	G.MouseY = V * WinH(G);
}

// the deepest visible control that takes input under UT's menu cursor (children last-drawn-first)
static function GUIComponent MenuHit(GUIComponent C)
{
	local int i;
	local GUIComponent Hit;
	local GUIMultiComponent M;
	local GUITabControl T;
	local GUIMultiOptionList L;

	if ( C == None || !C.bVisible )
		return None;
	// containers don't always enclose their children (footer buttons hang outside a tab panel), so look inside first
	// tab strips keep their buttons in TabStack and option lists their rows in Elements, not in Controls
	T = GUITabControl(C);
	if ( T != None )
		for ( i = 0; i < T.TabStack.Length; i++ )
			if ( T.TabStack[i] != None && T.TabStack[i].bVisible && T.TabStack[i].MenuState != MSAT_Disabled && T.TabStack[i].IsInBounds() )
				return T.TabStack[i];
	L = GUIMultiOptionList(C);
	if ( L != None )
		for ( i = 0; i < L.Elements.Length; i++ )
			if ( L.ElementVisible(i) )
			{
				Hit = MenuHit(L.Elements[i]);
				if ( Hit != None )
					return Hit;
			}
	M = GUIMultiComponent(C);
	if ( M != None && M.FocusedControl != None )
	{
		// the focused child (e.g. an open dropdown list) gets first claim, as in UT's own input handling
		Hit = MenuHit(M.FocusedControl);
		if ( Hit != None )
			return Hit;
	}
	if ( M != None )
		for ( i = M.Controls.Length - 1; i >= 0; i-- )
		{
			Hit = MenuHit(M.Controls[i]);
			if ( Hit != None )
				return Hit;
		}
	if ( C.bAcceptsInput && C.MenuState != MSAT_Disabled && C.IsInBounds() )
		return C;
	return None;
}

function Press(GUIController G)
{
	local GUIComponent Hit;
	PressedCtl = None;
	if ( G == None || G.ActivePage == None )
		return;
	Hit = MenuHit(G.ActivePage);
	if ( Hit == None )
	{
		Log("UT2004VR: menu click at "$G.MouseX$","$G.MouseY$" hit nothing", 'UT2004VR');
		return;
	}
	Log("UT2004VR: menu click -> "$Hit$" ("$Hit.Class$")", 'UT2004VR');
	PressedCtl = Hit;
	LastX = G.MouseX;
	LastY = G.MouseY;
	Hit.SetFocus(None);
	Hit.MenuStateChange(MSAT_Pressed);
	Hit.OnMousePressed(Hit, false);
}

function Held(GUIController G)
{
	if ( G == None || PressedCtl == None || !PressedCtl.bCaptureMouse )
		return;
	if ( G.MouseX != LastX || G.MouseY != LastY )
	{
		PressedCtl.OnCapturedMouseMove(G.MouseX - LastX, G.MouseY - LastY);
		LastX = G.MouseX;
		LastY = G.MouseY;
	}
}

function Release()
{
	local GUIComponent C;
	C = PressedCtl;
	PressedCtl = None;
	if ( C == None )
		return;
	C.OnMouseRelease(C);
	if ( C.MenuState == MSAT_Pressed )
		C.MenuStateChange(MSAT_Focused);
	if ( C.IsInBounds() )
		C.OnClick(C);
}

// debug: click at window uv, as the trigger does
function Click(GUIController G, float U, float V)
{
	if ( G == None || G.ResX <= 0 )
		return;
	G.MouseX = U * WinW(G);
	G.MouseY = V * WinH(G);
	Press(G);
	Release();
}

// debug: log every clickable control of the open menu with its centre in window uv
static function Dump(GUIController G)
{
	Log("UT2004VR: menu open="$(G != None && G.bActive)$" page="$G.ActivePage$" res "$G.ResX$"x"$G.ResY$" page bounds "
		$G.ActivePage.ActualLeft()$","$G.ActivePage.ActualTop()$" "$G.ActivePage.ActualWidth()$"x"$G.ActivePage.ActualHeight()$" mouse "$G.MouseX$","$G.MouseY, 'UT2004VR');
	if ( G != None && G.ActivePage != None && G.ResX > 0 )
		DumpCtl(G, G.ActivePage, 0);
}

static function string Caption(GUIComponent C)
{
	if ( GUIButton(C) != None ) return GUIButton(C).Caption;
	if ( moCheckBox(C) != None ) return moCheckBox(C).Caption$" checked="$moCheckBox(C).IsChecked();
	if ( moComboBox(C) != None ) return moComboBox(C).Caption$" = "$moComboBox(C).GetText();
	if ( moSlider(C) != None ) return moSlider(C).Caption$" = "$moSlider(C).GetValue();
	if ( GUIMenuOption(C) != None ) return GUIMenuOption(C).Caption;
	if ( GUIListBox(C) != None ) return "list items="$GUIListBox(C).List.ItemCount;
	return "";
}

static function DumpCtl(GUIController G, GUIComponent C, int Depth)
{
	local int i;
	local GUIMultiComponent M;
	local GUITabControl T;
	local GUIMultiOptionList L;
	if ( C == None || !C.bVisible || Depth > 10 ) return;
	if ( C.bAcceptsInput )
		Log("UT2004VR: menu ctl "$C.Name$" ("$C.Class.Name$") '"$Caption(C)$"' uv "$(C.ActualLeft()+C.ActualWidth()/2)/WinW(G)$","$(C.ActualTop()+C.ActualHeight()/2)/WinH(G), 'UT2004VR');
	T = GUITabControl(C);
	if ( T != None )
	{
		if ( T.ActiveTab != None )
			Log("UT2004VR: menu active tab '"$T.ActiveTab.Caption$"'", 'UT2004VR');
		for ( i = 0; i < T.TabStack.Length; i++ )
			DumpCtl(G, T.TabStack[i], Depth + 1);
	}
	L = GUIMultiOptionList(C);
	if ( L != None )
		for ( i = 0; i < L.Elements.Length; i++ )
			if ( L.ElementVisible(i) )
				DumpCtl(G, L.Elements[i], Depth + 1);
	M = GUIMultiComponent(C);
	if ( M != None )
		for ( i = 0; i < M.Controls.Length; i++ )
			DumpCtl(G, M.Controls[i], Depth + 1);
}
