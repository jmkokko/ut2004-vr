// UT2004VR d3d9.dll proxy (x64, for OldUnreal UT2004 3374 + D3D9Drv).
//
// - Loads the real d3d9.dll from System32 and wraps Direct3DCreate9(Ex).
// - Vtable-hooks IDirect3DDevice9::Present / Reset (and the implicit swap chain's Present).
// - On Present: copies the side-by-side backbuffer that VRHUD drew (left eye | right eye)
//   into a D3D11 texture and submits each half to SteamVR (OpenVR) with crop bounds that turn
//   UT's symmetric DrawPortal FOV into the headset's asymmetric per-eye frustum.
// - After Present: WaitGetPoses (paces the game to the headset), then sends head, hand, input,
//   eye and config packets as text datagrams to 127.0.0.1:7790 for VRLink.uc.
// - No headset / no SteamVR, or UT2004VR_MOCK=1: sends a synthetic head pose so the whole
//   UnrealScript side can be tested flat on the monitor.
#define WIN32_LEAN_AND_MEAN
#define _CRT_SECURE_NO_WARNINGS
#define NOMINMAX
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <d3d9.h>
#include <d3d11.h>
#include <dxgi.h>
#include <openvr.h>
#include <cmath>
#include <cstdio>
#include <cstdarg>
#include <string>
#include <algorithm>

#pragma comment(lib, "ws2_32.lib")
#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")

// ---------------------------------------------------------------------------
// logging
// ---------------------------------------------------------------------------
static FILE* g_log = nullptr;
static std::string g_dir;   // folder of this dll (the game's System folder)

static void Log(const char* fmt, ...)
{
	if (!g_log)
	{
		std::string p = g_dir + "UT2004VR_proxy.log";
		g_log = fopen(p.c_str(), "w");
		if (!g_log) return;
	}
	va_list ap;
	va_start(ap, fmt);
	vfprintf(g_log, fmt, ap);
	va_end(ap);
	fputc('\n', g_log);
	fflush(g_log);
}

// ---------------------------------------------------------------------------
// real d3d9
// ---------------------------------------------------------------------------
typedef IDirect3D9* (WINAPI* PFN_Create9)(UINT);
typedef HRESULT(WINAPI* PFN_Create9Ex)(UINT, IDirect3D9Ex**);
static HMODULE g_real = nullptr;

static FARPROC Real(const char* name)
{
	if (!g_real)
	{
		char sys[MAX_PATH];
		GetSystemDirectoryA(sys, MAX_PATH);
		std::string p = std::string(sys) + "\\d3d9.dll";
		g_real = LoadLibraryA(p.c_str());
		Log("loaded real d3d9 from %s -> %p", p.c_str(), g_real);
	}
	return g_real ? GetProcAddress(g_real, name) : nullptr;
}

// ---------------------------------------------------------------------------
// config
// ---------------------------------------------------------------------------
static float g_renderScale = 1.0f;   // UT2004VR_SCALE: fraction of SteamVR's recommended size
static int g_port = 7790;
static bool g_forceMock = false;
static bool g_mockDemo = false;
static bool g_dumpEyes = false;
static int g_mirrorEye = 0;       // MirrorEye: 0 left / 1 right eye copied into the desktop window, -1 off
static bool g_mirrorFill = true;  // MirrorFill: crop the eye to fill the window (no black bars)
static float g_mirrorZoom = 1.08f; // MirrorZoom: widen the mirror a little past the lens edge (the eye image is rendered wider)
static bool g_wantEx = true;      // GPUShare=1 (default): run the game on D3D9Ex and share the eye targets with D3D11
static bool g_isEx = false;       // the device really is D3D9Ex   // DumpEyes=1: write UT2004VR_eye0/1.bmp at frame 400
static float g_panelDist = 0.95f, g_panelWidth = 1.6f;   // PanelDistance, PanelWidth (m): the menu panel
static float g_sbDist = 1.0f, g_sbWidth = 1.5f;   // ScoreboardDistance, ScoreboardWidth (m): UT's scoreboard panel
static float g_specDist = 1.0f, g_specWidth = 1.3f, g_specDrop = 0.3f;   // SpectatorBarDistance/Width/Drop (m): UT's spectator bar, below eye level
static float g_followDeg = 0;   // PanelFollowDeg: main menus, look this far away for 1.5 s and the panel comes in front of you (0 off)
static float g_curve = 0.6f;    // PanelCurvature: 0 flat, 1 a cylinder centred on your head (radius = distance / this)
// standalone without a menu (a game that runs without VR, e.g. on a server): the whole window on a big screen
static bool g_screenMode = false;
static float g_screenDist = 2.4f, g_screenWidth = 3.2f; // ScreenDistance, ScreenWidth (m)
static bool g_mockDemo2 = false;
static bool g_mockPitchRoll = false;
static bool g_mockGun = false;
static bool g_mockSeated = false;
static bool g_mockHeading = false;
static bool g_mockJump = false;
static bool g_mockLookAway = false;  // MockDemo=9: worn, head straight (the menu comes up), then 40 deg, then 55 deg to one side
static bool g_mockCrouch = false;  // MockDemo=8: accidental vs deliberate crouch click, then jump out of crouch    // MockDemo=7: jump, then jump again at the apex (double jump) // MockDemo=6: look 60 deg right, then walk forward, then dodge L/R  // MockDemo=5: still, seated head that rises 20 cm     // MockDemo=4: still head, hand aiming forward, scripted fire // MockDemo=3: like 2, head pitched 20 and rolled 15  // MockDemo=2: head still, headset-sized window (projection calibration)   // MockDemo=1: scripted stick input in mock mode

static void ReadConfig()
{
	char buf[64];
	if (GetEnvironmentVariableA("UT2004VR_SCALE", buf, sizeof buf)) g_renderScale = (float)atof(buf);
	if (GetEnvironmentVariableA("UT2004VR_PORT", buf, sizeof buf)) g_port = atoi(buf);
	if (GetEnvironmentVariableA("UT2004VR_MOCK", buf, sizeof buf)) g_forceMock = buf[0] == '1';
	// same keys from UT2004VR_proxy.ini next to the dll
	std::string ini = g_dir + "UT2004VR_proxy.ini";
	if (GetPrivateProfileStringA("VR", "RenderScale", "", buf, sizeof buf, ini.c_str())) g_renderScale = (float)atof(buf);
	if (GetPrivateProfileStringA("VR", "Port", "", buf, sizeof buf, ini.c_str())) g_port = atoi(buf);
	if (GetPrivateProfileStringA("VR", "Mock", "", buf, sizeof buf, ini.c_str())) g_forceMock = g_forceMock || buf[0] == '1';
	if (GetPrivateProfileStringA("VR", "GPUShare", "", buf, sizeof buf, ini.c_str())) g_wantEx = buf[0] != '0';
	if (GetPrivateProfileStringA("VR", "MirrorEye", "", buf, sizeof buf, ini.c_str())) g_mirrorEye = atoi(buf);
	if (GetPrivateProfileStringA("VR", "MirrorFill", "", buf, sizeof buf, ini.c_str())) g_mirrorFill = buf[0] != '0';
	if (GetPrivateProfileStringA("VR", "MirrorZoom", "", buf, sizeof buf, ini.c_str())) g_mirrorZoom = std::max(0.5f, std::min(2.0f, (float)atof(buf)));
	if (GetPrivateProfileStringA("VR", "DumpEyes", "", buf, sizeof buf, ini.c_str())) g_dumpEyes = buf[0] == '1';
	if (GetPrivateProfileStringA("VR", "MockDemo", "", buf, sizeof buf, ini.c_str())) { g_mockDemo = buf[0] == '1'; g_mockDemo2 = buf[0] == '2' || buf[0] == '3'; g_mockPitchRoll = buf[0] == '3'; g_mockGun = buf[0] == '4'; g_mockSeated = buf[0] == '5'; g_mockHeading = buf[0] == '6'; g_mockJump = buf[0] == '7'; g_mockCrouch = buf[0] == '8'; g_mockLookAway = buf[0] == '9'; if (g_mockLookAway || g_mockSeated || g_mockHeading || g_mockJump || g_mockCrouch) g_mockDemo2 = true; }
	if (GetPrivateProfileStringA("VR", "PanelDistance", "", buf, sizeof buf, ini.c_str())) g_panelDist = std::max(0.5f, std::min(4.0f, (float)atof(buf)));
	if (GetPrivateProfileStringA("VR", "ScreenDistance", "", buf, sizeof buf, ini.c_str())) g_screenDist = std::max(0.5f, std::min(10.0f, (float)atof(buf)));
	if (GetPrivateProfileStringA("VR", "ScreenWidth", "", buf, sizeof buf, ini.c_str())) g_screenWidth = std::max(0.4f, std::min(10.0f, (float)atof(buf)));
	if (GetPrivateProfileStringA("VR", "PanelWidth", "", buf, sizeof buf, ini.c_str())) g_panelWidth = std::max(0.4f, std::min(4.0f, (float)atof(buf)));
	if (GetPrivateProfileStringA("VR", "ScoreboardDistance", "", buf, sizeof buf, ini.c_str())) g_sbDist = std::max(0.5f, std::min(4.0f, (float)atof(buf)));
	if (GetPrivateProfileStringA("VR", "ScoreboardWidth", "", buf, sizeof buf, ini.c_str())) g_sbWidth = std::max(0.3f, std::min(4.0f, (float)atof(buf)));
	if (GetPrivateProfileStringA("VR", "SpectatorBarDistance", "", buf, sizeof buf, ini.c_str())) g_specDist = std::max(0.5f, std::min(4.0f, (float)atof(buf)));
	if (GetPrivateProfileStringA("VR", "SpectatorBarWidth", "", buf, sizeof buf, ini.c_str())) g_specWidth = std::max(0.3f, std::min(4.0f, (float)atof(buf)));
	if (GetPrivateProfileStringA("VR", "SpectatorBarDrop", "", buf, sizeof buf, ini.c_str())) g_specDrop = std::max(-1.0f, std::min(1.5f, (float)atof(buf)));
	if (GetPrivateProfileStringA("VR", "PanelFollowDeg", "", buf, sizeof buf, ini.c_str())) g_followDeg = std::max(0.0f, std::min(170.0f, (float)atof(buf)));
	if (GetPrivateProfileStringA("VR", "PanelCurvature", "", buf, sizeof buf, ini.c_str())) g_curve = std::max(0.0f, std::min(1.0f, (float)atof(buf)));
	if (g_renderScale < 0.2f || g_renderScale > 2.0f) g_renderScale = 1.0f;
}

// ---------------------------------------------------------------------------
// UDP to VRLink.uc
// ---------------------------------------------------------------------------
static SOCKET g_sock = INVALID_SOCKET;
static sockaddr_in g_to = {};

struct Dest { int port; double seen; };
static Dest g_dst[4] = {};   // game links' announced ports
static double Now();
static void Announced(int port)
{
	int oldest = 0;
	for (int i = 0; i < 4; i++)
	{
		if (g_dst[i].port == port) { g_dst[i].seen = Now(); return; }
		if (g_dst[i].seen < g_dst[oldest].seen) oldest = i;
	}
	g_dst[oldest].port = port; g_dst[oldest].seen = Now();
	Log("game link on UDP %d", port);
}

static void Send(const char* fmt, ...)
{
	if (g_sock == INVALID_SOCKET)
	{
		WSADATA w;
		WSAStartup(MAKEWORD(2, 2), &w);
		g_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
		g_to.sin_family = AF_INET;
		g_to.sin_port = htons((u_short)g_port);
		inet_pton(AF_INET, "127.0.0.1", &g_to.sin_addr);
	}
	char b[256];
	va_list ap;
	va_start(ap, fmt);
	int n = vsnprintf(b, sizeof b, fmt, ap);
	va_end(ap);
	// UT2004's UdpLink.ReadText does not terminate the string at the datagram's end (leftovers of a
	// longer earlier packet get appended), so end every packet with " ;" and a NUL; VRLink cuts there
	if (n < 0) return;
	n = std::min(n, (int)sizeof b - 4);
	b[n++] = ' '; b[n++] = ';'; b[n++] = 0;
	// to every game link that announced its port ("N <port>") in the last 2 s; none yet: the old fixed port.
	// (Links of unloaded levels keep their sockets and UdpLink shares ports, so a fixed port could feed a dead one.)
	double now = Now();
	bool any = false;
	for (int i = 0; i < 4; i++)
		if (g_dst[i].port && now - g_dst[i].seen < 2000)
		{
			sockaddr_in c = g_to; c.sin_port = htons((u_short)g_dst[i].port);
			sendto(g_sock, b, n, 0, (sockaddr*)&c, sizeof c);
			any = true;
		}
	if (!any) sendto(g_sock, b, n, 0, (sockaddr*)&g_to, sizeof g_to);
}

// OpenVR (x right, y up, -z forward, right-handed, meters) -> Unreal (X forward, Y right, Z up)
struct V3 { float x, y, z; };
static V3 ToUE(float x, float y, float z) { return V3{ -z, x, y }; }

static void PoseVectors(const vr::HmdMatrix34_t& m, V3& pos, V3& fwd, V3& up)
{
	pos = ToUE(m.m[0][3], m.m[1][3], m.m[2][3]);
	fwd = ToUE(-m.m[0][2], -m.m[1][2], -m.m[2][2]);
	up = ToUE(m.m[0][1], m.m[1][1], m.m[2][1]);
}

static void SendPose(char tag, int a, const V3& p, const V3& f, const V3& u)
{
	Send("%c %d %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f", tag, a, p.x, p.y, p.z, f.x, f.y, f.z, u.x, u.y, u.z);
}

// ---------------------------------------------------------------------------
// VR state
// ---------------------------------------------------------------------------
static vr::IVRSystem* g_hmd = nullptr;
static bool g_vrTried = false;
static bool g_mock = false;
static vr::VRActionSetHandle_t g_set = 0;
static vr::VRActionHandle_t g_aMove = 0, g_aTurn = 0, g_aJump = 0, g_aCrouch = 0, g_aMenu = 0, g_aPoseL = 0, g_aPoseR = 0;
static vr::VRActionHandle_t g_aFire = 0, g_aAlt = 0, g_aNext = 0, g_aPrev = 0, g_aDodge = 0, g_aScores = 0;
static bool g_input = false;
static float g_tan[2][4];            // l r t b per eye
static float g_headFwdTan[2][2] = {}; // where the head's forward lands in each eye, in tangents (x right, y up)
static int g_fov = 100;              // integer horizontal portal FOV
static int g_eyeW = 0, g_eyeH = 0;   // wanted per-eye portal size (px)
static vr::TrackedDevicePose_t g_poses[vr::k_unMaxTrackedDeviceCount];
static vr::HmdMatrix34_t g_renderPose;   // pose sent to the game for the frame being rendered
static bool g_havePose = false;
static bool g_waited = false;     // a WaitGetPoses happened (Submit before it -> error 101)
static unsigned g_seq = 0;
static unsigned g_frames = 0;

// per-stage timing (ms), logged every 900 frames: where does the frame go?
static double g_tRead = 0, g_tUpload = 0, g_tSubmit = 0, g_tWait = 0, g_tGame = 0;
static LARGE_INTEGER g_qf;
static double Now()
{
	LARGE_INTEGER t;
	if (!g_qf.QuadPart) QueryPerformanceFrequency(&g_qf);
	QueryPerformanceCounter(&t);
	return t.QuadPart * 1000.0 / g_qf.QuadPart;
}

// square eye render targets (the ScriptedTextures), FOV covering the larger of the horizontal/vertical extent
static void SetEyeTargets(float hmax, float vmax, float pxPerTan)
{
	const float PI = 3.14159265f;
	float need = std::max(hmax, vmax);
	g_fov = std::min(170, (int)ceilf(2.0f * atanf(need) * 180.0f / PI));
	float h = tanf(g_fov * 0.5f * PI / 180.0f);
	int size = (int)(2 * h * pxPerTan * g_renderScale);
	size = std::max(512, std::min(4096, (size + 15) & ~15));
	g_eyeW = g_eyeH = size;
}

static void ComputeFrustum()
{
	float hmax = 0, vmax = 0;
	for (int e = 0; e < 2; e++)
	{
		float l, r, t, b;
		g_hmd->GetProjectionRaw((vr::EVREye)e, &l, &r, &t, &b);
		g_tan[e][0] = l; g_tan[e][1] = r; g_tan[e][2] = t; g_tan[e][3] = b;
		hmax = std::max(hmax, std::max(fabsf(l), fabsf(r)));
		vmax = std::max(vmax, std::max(fabsf(t), fabsf(b)));
		Log("eye %d tangents l=%.4f r=%.4f t=%.4f b=%.4f", e, l, r, t, b);
	}
	// eye-to-head transform: where does the head's forward point land in each eye's image?
	for (int e = 0; e < 2; e++)
	{
		vr::HmdMatrix34_t m = g_hmd->GetEyeToHeadTransform((vr::EVREye)e);
		// head forward (0,0,-1) in eye space = transpose(R) * (0,0,-1) = -(third row of R)
		float dx = -m.m[2][0], dy = -m.m[2][1], dz = -m.m[2][2];
		if (dz < -0.01f) { g_headFwdTan[e][0] = dx / -dz; g_headFwdTan[e][1] = dy / -dz; }
		Log("eye %d to head: pos %.4f %.4f %.4f  X(%.4f %.4f %.4f) Y(%.4f %.4f %.4f) Z(%.4f %.4f %.4f) -> head forward at tan %.4f, %.4f",
			e, m.m[0][3], m.m[1][3], m.m[2][3], m.m[0][0], m.m[1][0], m.m[2][0], m.m[0][1], m.m[1][1], m.m[2][1], m.m[0][2], m.m[1][2], m.m[2][2],
			g_headFwdTan[e][0], g_headFwdTan[e][1]);
	}
	uint32_t rw = 0, rh = 0;
	g_hmd->GetRecommendedRenderTargetSize(&rw, &rh);
	float dx = rw / (g_tan[0][1] - g_tan[0][0]);
	float dy = rh / (g_tan[0][3] - g_tan[0][2]);
	SetEyeTargets(hmax, vmax, std::max(dx, dy));
	Log("recommended %ux%u, fov %d, eye render targets %dx%d (scale %.2f)", rw, rh, g_fov, g_eyeW, g_eyeH, g_renderScale);
}

static void InitInput()
{
	std::string manifest = g_dir + "UT2004VR\\actions.json";
	vr::EVRInputError err = vr::VRInput()->SetActionManifestPath(manifest.c_str());
	if (err != vr::VRInputError_None) { Log("SetActionManifestPath(%s) failed: %d", manifest.c_str(), err); return; }
	vr::VRInput()->GetActionSetHandle("/actions/main", &g_set);
	vr::VRInput()->GetActionHandle("/actions/main/in/move", &g_aMove);
	vr::VRInput()->GetActionHandle("/actions/main/in/turn", &g_aTurn);
	vr::VRInput()->GetActionHandle("/actions/main/in/jump", &g_aJump);
	vr::VRInput()->GetActionHandle("/actions/main/in/crouch", &g_aCrouch);
	vr::VRInput()->GetActionHandle("/actions/main/in/menu", &g_aMenu);
	vr::VRInput()->GetActionHandle("/actions/main/in/pose_left", &g_aPoseL);
	vr::VRInput()->GetActionHandle("/actions/main/in/fire", &g_aFire);
	vr::VRInput()->GetActionHandle("/actions/main/in/altfire", &g_aAlt);
	vr::VRInput()->GetActionHandle("/actions/main/in/nextweapon", &g_aNext);
	vr::VRInput()->GetActionHandle("/actions/main/in/prevweapon", &g_aPrev);
	vr::VRInput()->GetActionHandle("/actions/main/in/dodge", &g_aDodge);
	vr::VRInput()->GetActionHandle("/actions/main/in/scoreboard", &g_aScores);
	vr::VRInput()->GetActionHandle("/actions/main/in/pose_right", &g_aPoseR);
	g_input = true;
	Log("input actions ready (%s)", manifest.c_str());
}

static void InitVR()
{
	if (g_vrTried) return;
	g_vrTried = true;
	ReadConfig();
	if (g_forceMock) { g_mock = true; Log("mock mode (forced)"); return; }
	if (!vr::VR_IsRuntimeInstalled() || !vr::VR_IsHmdPresent())
	{
		g_mock = true;
		Log("no SteamVR runtime or no headset -> mock mode");
		return;
	}
	vr::EVRInitError e = vr::VRInitError_None;
	g_hmd = vr::VR_Init(&e, vr::VRApplication_Scene);
	if (e != vr::VRInitError_None || !g_hmd || !vr::VRCompositor())
	{
		Log("VR_Init failed: %s -> mock mode", vr::VR_GetVRInitErrorAsEnglishDescription(e));
		g_hmd = nullptr;
		g_mock = true;
		return;
	}
	vr::VRCompositor()->SetTrackingSpace(vr::TrackingUniverseStanding);
	ComputeFrustum();
	InitInput();
	Log("SteamVR ready");
}

// ---------------------------------------------------------------------------
// D3D11 side (the texture OpenVR reads)
// ---------------------------------------------------------------------------
static ID3D11Device* g_d11 = nullptr;
static ID3D11DeviceContext* g_ctx = nullptr;
// ---------------------------------------------------------------------------
// Eye render targets: the engine creates them for VRPlayerController's ScriptedTextures. We keep a
// reference to every square render-target texture of the requested size and tell left from right by
// the 4x4 tag the script draws in the corner (red = left, blue = right).
// ---------------------------------------------------------------------------
struct Candidate { IDirect3DTexture9* tex; int eye; int tries; HANDLE share; ID3D11Texture2D* tex11; };
static Candidate g_cand[8];
static int g_nCand = 0;
static IDirect3DSurface9* g_sysmem = nullptr;
static UINT g_sysSize = 0;
static D3DFORMAT g_sysFmt = D3DFMT_UNKNOWN;
static ID3D11Texture2D* g_eye11[2] = {};
static UINT g_eye11Size = 0;

static void ReleaseCandidates()
{
	for (int i = 0; i < g_nCand; i++)
	{
		if (g_cand[i].tex) g_cand[i].tex->Release();
		if (g_cand[i].tex11) g_cand[i].tex11->Release();
	}
	g_nCand = 0;
	if (g_sysmem) { g_sysmem->Release(); g_sysmem = nullptr; }
	g_sysSize = 0;
}

static void AddCandidate(IDirect3DTexture9* t, HANDLE share)
{
	if (g_nCand == 8)
	{
		g_cand[0].tex->Release();
		if (g_cand[0].tex11) g_cand[0].tex11->Release();
		memmove(&g_cand[0], &g_cand[1], sizeof(Candidate) * 7);
		g_nCand = 7;
	}
	t->AddRef();
	g_cand[g_nCand++] = Candidate{ t, -1, 0, share, nullptr };
}

static bool Ensure11(UINT size)
{
	if (!g_d11)
	{
		// the headset's GPU, not just the default adapter (Ryzen CPUs have an iGPU too)
		IDXGIAdapter* adapter = nullptr;
		int32_t idx = -1;
		if (g_hmd) g_hmd->GetDXGIOutputInfo(&idx);
		IDXGIFactory1* fac = nullptr;
		if (idx >= 0 && SUCCEEDED(CreateDXGIFactory1(__uuidof(IDXGIFactory1), (void**)&fac)))
		{
			fac->EnumAdapters((UINT)idx, &adapter);
			fac->Release();
		}
		if (adapter)
		{
			DXGI_ADAPTER_DESC ad;
			adapter->GetDesc(&ad);
			Log("D3D11 on adapter %d: %ls", idx, ad.Description);
		}
		HRESULT hr = D3D11CreateDevice(adapter, adapter ? D3D_DRIVER_TYPE_UNKNOWN : D3D_DRIVER_TYPE_HARDWARE, nullptr, 0, nullptr, 0, D3D11_SDK_VERSION, &g_d11, nullptr, &g_ctx);
		if (adapter) adapter->Release();
		if (FAILED(hr)) { Log("D3D11CreateDevice failed %08x", hr); return false; }
	}
	if (size == 0) return true;
	if (g_eye11[0] && g_eye11Size == size) return true;
	for (int e = 0; e < 2; e++) if (g_eye11[e]) { g_eye11[e]->Release(); g_eye11[e] = nullptr; }
	D3D11_TEXTURE2D_DESC d = {};
	d.Width = size; d.Height = size; d.MipLevels = 1; d.ArraySize = 1;
	d.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
	d.SampleDesc.Count = 1;
	d.Usage = D3D11_USAGE_DEFAULT;
	d.BindFlags = D3D11_BIND_SHADER_RESOURCE;
	for (int e = 0; e < 2; e++)
	{
		HRESULT hr = g_d11->CreateTexture2D(&d, nullptr, &g_eye11[e]);
		if (FAILED(hr)) { Log("CreateTexture2D %u failed %08x", size, hr); return false; }
	}
	g_eye11Size = size;
	Log("D3D11 eye textures %ux%u", size, size);
	return true;
}

// render target -> system memory, locked; returns the tag colour's eye (-1 = none) and leaves g_sysmem locked
static int ReadTarget(IDirect3DDevice9* dev, IDirect3DTexture9* tex, D3DLOCKED_RECT& lr, UINT& size)
{
	IDirect3DSurface9* surf = nullptr;
	if (FAILED(tex->GetSurfaceLevel(0, &surf)) || !surf) return -2;
	D3DSURFACE_DESC d;
	surf->GetDesc(&d);
	size = d.Width;
	if (!g_sysmem || g_sysSize != d.Width || g_sysFmt != d.Format)
	{
		if (g_sysmem) g_sysmem->Release();
		g_sysmem = nullptr;
		dev->CreateOffscreenPlainSurface(d.Width, d.Height, d.Format, D3DPOOL_SYSTEMMEM, &g_sysmem, nullptr);
		g_sysSize = d.Width; g_sysFmt = d.Format;
	}
	HRESULT hr = g_sysmem ? dev->GetRenderTargetData(surf, g_sysmem) : E_FAIL;
	surf->Release();
	if (FAILED(hr) || FAILED(g_sysmem->LockRect(&lr, nullptr, D3DLOCK_READONLY))) return -2;
	const unsigned char* px = (const unsigned char*)lr.pBits + lr.Pitch * 3 + 4 * 3;   // BGRA at (3,3)
	if (px[2] > 200 && px[0] < 60) return 0;
	if (px[0] > 200 && px[2] < 60) return 1;
	return -1;
}

static bool g_rightOK = false;
static vr::HmdMatrix34_t g_rightPose;

// ---------------------------------------------------------------------------
// VR menu panel: while UT's menu is open (the game tells us over UDP 7791: "P 1 c" controller mode,
// "P 1 k" keyboard/mouse, "P 0"), the desktop window (menu on black) is copied into a texture and drawn into
// both eye images as a flat panel fixed in the room, 1.4 m in front of where the head faced when it opened.
// In controller mode the right hand's ray picks a point on it: the OS cursor goes there and the trigger
// clicks - only while UT2004 is the foreground window.
// ---------------------------------------------------------------------------
static SOCKET g_rx = INVALID_SOCKET;
static bool g_menuOpen = false, g_menuCtrl = false, g_panelPlaced = false;
static float g_pC[3], g_pR[3], g_pU[3], g_pN[3], g_pHalfW = 0.8f, g_pHalfH = 0.45f;
static bool g_panelMips = false;
static float g_pO[3], g_pRad = 0;   // curved panel: the cylinder's axis point (behind the centre) and radius; 0 = flat

// a point on the panel, x and y in -1..1 (right, up): on the cylinder when curved, so every column faces you
static void PanelPoint(float x, float y, float* w)
{
	if (g_pRad <= 0)
	{
		for (int k = 0; k < 3; k++) w[k] = g_pC[k] + g_pR[k] * x * g_pHalfW + g_pU[k] * y * g_pHalfH;
		return;
	}
	float a = x * g_pHalfW / g_pRad, sa = sinf(a) * g_pRad, ca = cosf(a) * g_pRad;
	for (int k = 0; k < 3; k++) w[k] = g_pO[k] + g_pR[k] * sa - g_pN[k] * ca + g_pU[k] * y * g_pHalfH;
}
static IDirect3DTexture9* g_panelTex = nullptr;
static UINT g_panelW = 0, g_panelH = 0;
static HWND g_hwnd = nullptr;
static bool g_oldTrig = false;
static float g_cursorU = -1, g_cursorV = -1;     // UT's menu cursor, in window coordinates 0..1 (from the game)
static float g_menuRect[4] = { 0, 0, 1, 1 };     // the menu page in the window (x, y, w, h, 0..1): the panel shows only that
static bool g_mouseDown = false;
static bool g_beamOK = false;                     // controller ray: tip -> hit point (tracking space)
// standalone: no VR game is rendering (UT's main menus, "M 1" from VRConsole); the proxy draws the headset view
// itself, a dark room with the menu panel, into its own two eye targets
static double g_standaloneUntil = 0;
static bool g_standaloneScreen = false;   // "M 2": a game without VR (the window on a big screen); "M 1": menus
static void ScorePacket(const char* b);  // "S <kind> <top>"/"S 0" from the game (the scoreboard module below)
static bool g_menuDialog = false;      // the menu page is a dialog drawn alone on black ("R ... 1")
static double g_vrGameAt = 0;            // "M 0": a VR game renders its eyes
static double g_vrSince = 0;             // ... since when (the first "M 0" after menus)
static bool g_eyesStale = false;         // the eye targets we know are from before the menus (the intro, the last
                                         // level): not shown until the new level's are found (or 1.5 s of "M 0")
static IDirect3DTexture9* g_ownEye[2] = {};
static HANDLE g_ownShare[2] = {};
static ID3D11Texture2D* g_own11[2] = {};
static UINT g_ownSize = 0;
static float g_beamA[3], g_beamB[3];

static void PollGame()
{
	if (g_rx == INVALID_SOCKET)   // bound early (HookDevice), before the game's UdpLinks could take the port
	{
		static bool wsa = false;
		if (!wsa) { WSADATA w; WSAStartup(MAKEWORD(2, 2), &w); wsa = true; }   // may run before the first Send
		g_rx = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
		sockaddr_in a = {}; a.sin_family = AF_INET; a.sin_port = htons((u_short)(g_port + 1));
		inet_pton(AF_INET, "127.0.0.1", &a.sin_addr);
		if (bind(g_rx, (sockaddr*)&a, sizeof a) != 0) { Log("panel socket bind failed"); closesocket(g_rx); g_rx = INVALID_SOCKET - 1; return; }
		u_long nb = 1; ioctlsocket(g_rx, FIONBIO, &nb);
		Log("listening for game messages on UDP %d", g_port + 1);
	}
	if (g_rx == INVALID_SOCKET || g_rx == INVALID_SOCKET - 1) return;
	char b[128];
	for (int i = 0; i < 64; i++)
	{
		int n = recv(g_rx, b, sizeof b - 1, 0);
		if (n <= 0) break;
		b[n] = 0;
		if (b[0] == 'Q') { float u, v; if (sscanf(b + 1, "%f %f", &u, &v) == 2) { g_cursorU = u; g_cursorV = v; } }
		if (b[0] == 'R')
		{
			float r[4];
			int dlg = 0;
			if (sscanf(b + 1, "%f %f %f %f %d", &r[0], &r[1], &r[2], &r[3], &dlg) >= 4 && r[2] > 0.05f && r[3] > 0.05f)
			{
				g_menuDialog = dlg != 0;   // a dialog drawn alone on black: keyed in the main menus too
				// exactly the page (a margin showed the page behind a dialog, or the black around an in-game menu, as a
				// frame); keep inside the window
				r[0] = std::max(0.0f, r[0]); r[1] = std::max(0.0f, r[1]);
				r[2] = std::min(1.0f - r[0], r[2]); r[3] = std::min(1.0f - r[1], r[3]);
				memcpy(g_menuRect, r, sizeof r);
			}
		}
		if (b[0] == 'N') { int port = atoi(b + 1); if (port > 1024 && port < 65536) Announced(port); }
		if (b[0] == 'M')
		{
			if (b[2] == '0') { if (g_vrGameAt == 0) g_vrSince = Now(); g_vrGameAt = Now(); }
			else
			{
				bool scr = b[2] == '2';
				if (Now() > g_standaloneUntil || scr != g_standaloneScreen) Log("standalone view: %s (no VR game running) t=%.0f", scr ? "game window" : "menus", Now());
				g_standaloneUntil = Now() + 1500;
				g_standaloneScreen = scr;
				g_vrGameAt = 0;   // the latest word wins (a leaving VR game's last "M 0" made the view flip)
				g_eyesStale = true;
			}
		}
		if (b[0] == 'S') ScorePacket(b);
		if (b[0] == 'P')
		{
			bool open = b[2] == '1';
			g_menuCtrl = open && b[4] == 'c';
			if (open != g_menuOpen) { g_menuOpen = open; g_panelPlaced = false; Log("menu %s (%s) t=%.0f", open ? "open" : "closed", g_menuCtrl ? "controller" : "keyboard/mouse", Now()); }
		}
	}
}

static void M34Mul(const vr::HmdMatrix34_t& A, const vr::HmdMatrix34_t& B, vr::HmdMatrix34_t& C)
{
	for (int r = 0; r < 3; r++)
		for (int c = 0; c < 4; c++)
		{
			C.m[r][c] = A.m[r][0] * B.m[0][c] + A.m[r][1] * B.m[1][c] + A.m[r][2] * B.m[2][c] + (c == 3 ? A.m[r][3] : 0);
		}
}

// SteamVR's seated calibration (where "forward" and the seated head are, as SteamVR Home uses), in the standing
// space we track in; false if there is none
static bool SeatedPose(vr::HmdMatrix34_t& m)
{
	if (!g_hmd) return false;
	m = g_hmd->GetSeatedZeroPoseToStandingAbsoluteTrackingPose();
	float s = 0;
	for (int r = 0; r < 3; r++) for (int c = 0; c < 3; c++) s += fabsf(m.m[r][c]);
	return s > 0.5f;
}
static bool g_worn = false;
static bool g_panelRecentred = false;
static bool g_placingScore = false;
static int g_sbKind = 0;      // 1 UT's scoreboard, 2 UT's spectator bar
static float g_sbTop = 0;     // the window share it covers, from the top (0..1): the panel shows only that strip
static float g_hlDist = 2.5f, g_hlHalfW = 1.18f, g_hlUp = -0.2f;   // kind 3, the game type's HUD: head-locked, metres   // PlacePanel for the scoreboard (its own distance)
static bool g_panelSeated = false, g_panelSeatedWorn = false;   // placed facing the calibration; the headset was worn then   // the next placement follows the headset (you looked away from the panel)

// the panel in front of a pose: the headset's, or (bSeated) the seated calibration - the main menus at startup
// come up while the headset may still lie on the desk, facing anywhere
static void PlacePanel(bool bSeated = false)
{
	// the direction from the seated calibration; the position from your head once you wear the headset (the
	// calibration's own position can be half a metre off and well below your head)
	vr::HmdMatrix34_t sm;
	g_panelSeated = bSeated && SeatedPose(sm);
	const vr::HmdMatrix34_t& m = g_panelSeated ? sm : g_renderPose;
	const vr::HmdMatrix34_t& at = (g_panelSeated && !g_worn) ? sm : g_renderPose;
	if (g_panelSeated) Log("panel facing the seated calibration, at the %s", g_worn ? "head" : "calibration (headset not worn)");
	g_panelSeatedWorn = g_worn;
	float f[3] = { -m.m[0][2], 0, -m.m[2][2] };            // forward, flattened
	float l = sqrtf(f[0] * f[0] + f[2] * f[2]); if (l < 1e-3f) { f[0] = 0; f[2] = -1; l = 1; }
	f[0] /= l; f[2] /= l;
	float dist = g_placingScore ? (g_sbKind == 2 ? g_specDist : g_sbDist) : g_screenMode ? g_screenDist : g_panelDist;
	g_pC[0] = at.m[0][3] + f[0] * dist; g_pC[1] = at.m[1][3]; g_pC[2] = at.m[2][3] + f[2] * dist;
	if (g_placingScore && g_sbKind == 2) g_pC[1] -= g_specDrop;   // the spectator bar: below eye level, like on screen
	g_pR[0] = -f[2]; g_pR[1] = 0; g_pR[2] = f[0];            // forward x up(0,1,0)
	g_pU[0] = 0; g_pU[1] = 1; g_pU[2] = 0;
	g_pN[0] = -f[0]; g_pN[1] = 0; g_pN[2] = -f[2];          // faces the viewer
	g_pRad = g_curve > 0.01f ? dist / g_curve : 0;
	for (int k = 0; k < 3; k++) g_pO[k] = g_pC[k] + g_pN[k] * g_pRad;   // N faces the viewer: the axis is behind you... at the head for curvature 1
	g_panelPlaced = true;
	Log("panel placed at %.2f %.2f %.2f, curve radius %.2f", g_pC[0], g_pC[1], g_pC[2], g_pRad);
}

// ---------------------------------------------------------------------------
// UT's own scoreboard in the headset. While it is up the game says "S 1" and, every few frames, draws it alone on
// black and then on white with a two-pixel marker at the bottom right. The pair gives back its transparency
// (alpha = 1 - (white - black), the black one is the colour premultiplied by it), so it goes over the game in the
// eyes the way it does on a monitor. Those two frames never reach the desktop: the previous picture is put back.
// ---------------------------------------------------------------------------
static double g_sbAt = 0;                         // last "S 1"
static IDirect3DTexture9* g_sbTex[2] = {};        // the scoreboard over black / over white
static bool g_sbHave[2] = {}, g_sbMips = false, g_sbPlaced = false, g_sbLastOK = false, g_sbPSTried = false;
static UINT g_sbW = 0, g_sbH = 0;
static IDirect3DSurface9* g_sbLast = nullptr;     // the last ordinary window picture
static IDirect3DSurface9* g_sbMarkRT = nullptr;   // 2x1 copy of the marker corner, and its CPU-side twin
static IDirect3DSurface9* g_sbMarkSys = nullptr;
static IDirect3DPixelShader9* g_sbPS = nullptr;


static void ScorePacket(const char* b)
{
	int kind = atoi(b + 2);
	const char* sp = strchr(b + 2, ' ');
	float top = sp ? std::max(0.0f, std::min(0.95f, (float)atof(sp + 1))) : 0.0f;
	if (kind <= 0)
	{
		if (g_sbAt > 0) Log("overlay down t=%.0f", Now());
		g_sbAt = 0; g_sbKind = 0; g_sbHave[0] = g_sbHave[1] = false;
		return;
	}
	// another overlay (scoreboard <-> spectator bar): new pictures, placed again
	if (kind != g_sbKind) { g_sbHave[0] = g_sbHave[1] = false; g_sbPlaced = false; }
	if (Now() - g_sbAt > 1000 || kind != g_sbKind) Log("overlay %s up (top %.3f) t=%.0f", kind == 3 ? "game HUD" : kind == 2 ? "spectator bar" : "scoreboard", top, Now());
	if (kind == 3 && sp)
	{
		// "S 3 0 <distance> <half width> <centre up>"
		float t, d, hw, up;
		if (sscanf(b + 2, "%*d %f %f %f %f", &t, &d, &hw, &up) == 4 && d > 0.2f && hw > 0.05f) { g_hlDist = d; g_hlHalfW = hw; g_hlUp = up; }
	}
	g_sbKind = kind; g_sbTop = top; g_sbAt = Now();
}

static bool ScoreUp() { return g_sbAt > 0 && Now() - g_sbAt < 1000; }

static void ScoreRelease()
{
	for (int k = 0; k < 2; k++) { if (g_sbTex[k]) g_sbTex[k]->Release(); g_sbTex[k] = nullptr; g_sbHave[k] = false; }
	if (g_sbLast) g_sbLast->Release(); g_sbLast = nullptr; g_sbLastOK = false;
	if (g_sbMarkRT) g_sbMarkRT->Release(); g_sbMarkRT = nullptr;
	if (g_sbMarkSys) g_sbMarkSys->Release(); g_sbMarkSys = nullptr;
	if (g_sbPS) g_sbPS->Release(); g_sbPS = nullptr; g_sbPSTried = false;
	g_sbW = g_sbH = 0;
}

// pixel shaders compiled at runtime (d3dcompiler_47 ships with Windows)
static IDirect3DPixelShader9* CompilePS(IDirect3DDevice9* dev, const char* name, const char* src)
{
	typedef HRESULT(WINAPI* PFN_Compile)(LPCVOID, SIZE_T, LPCSTR, const void*, void*, LPCSTR, LPCSTR, UINT, UINT, ID3DBlob**, ID3DBlob**);
	static PFN_Compile compile = nullptr;
	static bool tried = false;
	if (!tried)
	{
		tried = true;
		HMODULE m = LoadLibraryA("d3dcompiler_47.dll");
		compile = m ? (PFN_Compile)GetProcAddress(m, "D3DCompile") : nullptr;
		if (!compile) Log("no d3dcompiler_47.dll: no scoreboard panel, menus opaque");
	}
	if (!compile) return nullptr;
	IDirect3DPixelShader9* ps = nullptr;
	ID3DBlob* code = nullptr; ID3DBlob* err = nullptr;
	HRESULT hr = compile(src, strlen(src), name, nullptr, nullptr, "main", "ps_2_0", 0, 0, &code, &err);
	if (SUCCEEDED(hr) && code) dev->CreatePixelShader((const DWORD*)code->GetBufferPointer(), &ps);
	Log("%s shader: %s", name, ps ? "ok" : (err ? (const char*)err->GetBufferPointer() : "failed"));
	if (code) code->Release();
	if (err) err->Release();
	return ps;
}

// the scoreboard pair -> colour + alpha
static void ScoreShader(IDirect3DDevice9* dev)
{
	if (g_sbPS || g_sbPSTried) return;
	g_sbPSTried = true;
	g_sbPS = CompilePS(dev, "scoreboard",
		"sampler B : register(s0); sampler W : register(s1);\n"
		"float4 main(float2 uv : TEXCOORD0) : COLOR {\n"
		"  float3 b = tex2D(B, uv).rgb, w = tex2D(W, uv).rgb;\n"
		"  float a = saturate(1 - dot(w - b, float3(0.3333, 0.3333, 0.3334)));\n"
		"  return float4(b, a); }\n");
}

// in-game menus are drawn on pure black: that black becomes see-through (the bevelled corners, the edges of the
// crop), so the panel has the menu's own shape; anything darker than ~2/255 is gone, fully opaque from ~6/255
static IDirect3DPixelShader9* g_keyPS = nullptr;
static bool g_keyPSTried = false;
static void KeyShader(IDirect3DDevice9* dev)
{
	if (g_keyPS || g_keyPSTried) return;
	g_keyPSTried = true;
	g_keyPS = CompilePS(dev, "menu key",
		"sampler P : register(s0);\n"
		"float4 main(float2 uv : TEXCOORD0) : COLOR {\n"
		"  float4 c = tex2D(P, uv);\n"
		"  float m = max(c.r, max(c.g, c.b));\n"
		"  return float4(c.rgb, saturate((m - 0.008) * 60)); }\n");
}

// before Present: a capture frame goes into its texture and the window gets the previous picture back
static void ScoreCapture(IDirect3DDevice9* dev)
{
	if (!ScoreUp()) { g_sbHave[0] = g_sbHave[1] = false; g_sbLastOK = false; return; }
	ScoreShader(dev);
	IDirect3DSurface9* bb = nullptr;
	if (FAILED(dev->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &bb)) || !bb) return;
	D3DSURFACE_DESC bd; bb->GetDesc(&bd);
	if (g_sbW != bd.Width || g_sbH != bd.Height)
	{
		IDirect3DPixelShader9* ps = g_sbPS; g_sbPS = nullptr;   // keep the shader across a resize
		ScoreRelease();
		g_sbPS = ps; g_sbPSTried = ps != nullptr;
		for (int k = 0; k < 2; k++)
		{
			g_sbMips = SUCCEEDED(dev->CreateTexture(bd.Width, bd.Height, 0, D3DUSAGE_RENDERTARGET | D3DUSAGE_AUTOGENMIPMAP, D3DFMT_X8R8G8B8, D3DPOOL_DEFAULT, &g_sbTex[k], nullptr));
			if (!g_sbMips) dev->CreateTexture(bd.Width, bd.Height, 1, D3DUSAGE_RENDERTARGET, D3DFMT_X8R8G8B8, D3DPOOL_DEFAULT, &g_sbTex[k], nullptr);
		}
		dev->CreateRenderTarget(bd.Width, bd.Height, bd.Format, D3DMULTISAMPLE_NONE, 0, FALSE, &g_sbLast, nullptr);
		dev->CreateRenderTarget(2, 1, D3DFMT_X8R8G8B8, D3DMULTISAMPLE_NONE, 0, FALSE, &g_sbMarkRT, nullptr);
		dev->CreateOffscreenPlainSurface(2, 1, D3DFMT_X8R8G8B8, D3DPOOL_SYSTEMMEM, &g_sbMarkSys, nullptr);
		g_sbW = bd.Width; g_sbH = bd.Height;
		Log("scoreboard capture %ux%u mipmaps %d", bd.Width, bd.Height, (int)g_sbMips);
	}
	int kind = -1;
	if (g_sbMarkRT && g_sbMarkSys)
	{
		RECT mr = { (LONG)bd.Width - 2, (LONG)bd.Height - 1, (LONG)bd.Width, (LONG)bd.Height };
		D3DLOCKED_RECT lr;
		if (SUCCEEDED(dev->StretchRect(bb, &mr, g_sbMarkRT, nullptr, D3DTEXF_POINT))
			&& SUCCEEDED(dev->GetRenderTargetData(g_sbMarkRT, g_sbMarkSys))
			&& SUCCEEDED(g_sbMarkSys->LockRect(&lr, nullptr, D3DLOCK_READONLY)))
		{
			DWORD p0 = ((DWORD*)lr.pBits)[0] & 0xFFFFFF, p1 = ((DWORD*)lr.pBits)[1] & 0xFFFFFF;
			g_sbMarkSys->UnlockRect();
			if (p0 == 0xFF00FF && p1 == 0x00FF00) kind = 0;
			else if (p0 == 0x00FFFF && p1 == 0xFF0000) kind = 1;
		}
	}
	if (kind >= 0)
	{
		IDirect3DSurface9* ts = nullptr;
		if (g_sbTex[kind] && SUCCEEDED(g_sbTex[kind]->GetSurfaceLevel(0, &ts)) && ts)
		{
			if (SUCCEEDED(dev->StretchRect(bb, nullptr, ts, nullptr, D3DTEXF_NONE)))
			{
				if (g_sbMips) g_sbTex[kind]->GenerateMipSubLevels();
				if (!g_sbHave[kind] && g_sbHave[1 - kind]) Log("scoreboard captured t=%.0f", Now());
				g_sbHave[kind] = true;
			}
			ts->Release();
		}
		if (g_sbLastOK) dev->StretchRect(g_sbLast, nullptr, bb, nullptr, D3DTEXF_NONE);
	}
	else if (g_sbLast && SUCCEEDED(dev->StretchRect(bb, nullptr, g_sbLast, nullptr, D3DTEXF_NONE)))
		g_sbLastOK = true;
	bb->Release();
}

// copy the window (menu on black) into the panel texture
static bool CapturePanel(IDirect3DDevice9* dev)
{
	IDirect3DSurface9* bb = nullptr;
	if (FAILED(dev->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &bb)) || !bb) return false;
	D3DSURFACE_DESC bd; bb->GetDesc(&bd);
	static const float full[4] = { 0, 0, 1, 1 };
	const float* r = g_screenMode ? full : g_menuRect;   // the menu page, or (screen mode) the whole window
	if (!g_panelTex || g_panelW != bd.Width || g_panelH != bd.Height)
	{
		if (g_panelTex) { g_panelTex->Release(); g_panelTex = nullptr; }
		// mipmapped: the window is sampled down a lot in the eye, and without mips its text and lines shimmered (moire)
		g_panelMips = SUCCEEDED(dev->CreateTexture(bd.Width, bd.Height, 0, D3DUSAGE_RENDERTARGET | D3DUSAGE_AUTOGENMIPMAP, D3DFMT_X8R8G8B8, D3DPOOL_DEFAULT, &g_panelTex, nullptr));
		if (!g_panelMips)
			dev->CreateTexture(bd.Width, bd.Height, 1, D3DUSAGE_RENDERTARGET, D3DFMT_X8R8G8B8, D3DPOOL_DEFAULT, &g_panelTex, nullptr);
		Log("panel texture %ux%u mipmaps %d", bd.Width, bd.Height, (int)g_panelMips);
		g_panelW = bd.Width; g_panelH = bd.Height;
	}
	bool ok = false;
	if (g_panelTex)
	{
		IDirect3DSurface9* ps = nullptr;
		if (SUCCEEDED(g_panelTex->GetSurfaceLevel(0, &ps)) && ps)
		{
			RECT src = { (LONG)(r[0] * bd.Width), (LONG)(r[1] * bd.Height),
				(LONG)((r[0] + r[2]) * bd.Width), (LONG)((r[1] + r[3]) * bd.Height) };
			ok = SUCCEEDED(dev->StretchRect(bb, &src, ps, nullptr, D3DTEXF_LINEAR));
			ps->Release();
			if (ok && g_panelMips) g_panelTex->GenerateMipSubLevels();
		}
	}
	g_pHalfW = (g_screenMode ? g_screenWidth : g_panelWidth) * 0.5f;
	g_pHalfH = g_pHalfW * (r[3] * bd.Height) / (r[2] * bd.Width);
	bb->Release();
	return ok;
}

struct PanelVert { float x, y, z, rhw, u, v; };


// draw the panel into one eye's render target, projected with the pose this frame was rendered with
static void DrawPanelInEye(IDirect3DDevice9* dev, IDirect3DTexture9* eyeTex, int e, bool score = false, bool key = false)
{
	vr::HmdMatrix34_t eh = g_hmd ? g_hmd->GetEyeToHeadTransform((vr::EVREye)e) : vr::HmdMatrix34_t{};
	if (!g_hmd) { memset(&eh, 0, sizeof eh); eh.m[0][0] = eh.m[1][1] = eh.m[2][2] = 1; eh.m[0][3] = e ? 0.032f : -0.032f; }
	vr::HmdMatrix34_t E; M34Mul(g_renderPose, eh, E);
	IDirect3DSurface9* rt = nullptr;
	if (FAILED(eyeTex->GetSurfaceLevel(0, &rt)) || !rt) return;
	D3DSURFACE_DESC d; rt->GetDesc(&d);
	const float PI = 3.14159265f;
	float h = tanf(g_fov * 0.5f * PI / 180.0f);
	// columns of a strip: a curved panel bends along its width (flat: they just lie in a plane)
	const int NC = 24;
	PanelVert v[2 * (NC + 1)];
	bool behind[NC + 1] = {};
	for (int i = 0; i < 2 * (NC + 1); i++)
	{
		float x = -1 + 2.0f * (i / 2) / NC, y = (i & 1) ? -1.0f : 1.0f, w[3], p[3];
		PanelPoint(x, y, w);
		for (int k = 0; k < 3; k++) p[k] = w[k] - E.m[k][3];
		// into eye space: transpose of the rotation
		float q[3];
		for (int k = 0; k < 3; k++) q[k] = E.m[0][k] * p[0] + E.m[1][k] * p[1] + E.m[2][k] * p[2];
		// a point behind the eye: its column strips aren't drawn (they're outside the view anyway; the wide curved
		// panel's far edge goes behind you when you turn ~40 deg, and skipping the whole panel made it vanish)
		if (q[2] > -0.05f) { behind[i / 2] = true; q[2] = -0.05f; }
		float tx = q[0] / -q[2], ty = q[1] / -q[2];
		v[i].x = (tx / h + 1) * 0.5f * d.Width - 0.5f;
		v[i].y = (1 - ty / h) * 0.5f * d.Height - 0.5f;
		v[i].z = 0.0f;
		v[i].rhw = 1.0f / -q[2];
		v[i].u = (x + 1) * 0.5f; v[i].v = (i & 1) ? 1.0f : (score ? g_sbTop : 0.0f);
	}
	IDirect3DStateBlock9* sb = nullptr;
	dev->CreateStateBlock(D3DSBT_ALL, &sb);
	IDirect3DSurface9* oldRT = nullptr; IDirect3DSurface9* oldDS = nullptr;
	dev->GetRenderTarget(0, &oldRT); dev->GetDepthStencilSurface(&oldDS);
	dev->SetRenderTarget(0, rt);
	dev->SetDepthStencilSurface(nullptr);
	D3DVIEWPORT9 vp = { 0, 0, d.Width, d.Height, 0, 1 };
	dev->SetViewport(&vp);
	dev->SetVertexShader(nullptr); dev->SetPixelShader(nullptr);
	dev->SetFVF(D3DFVF_XYZRHW | D3DFVF_TEX1);
	dev->SetRenderState(D3DRS_ZENABLE, FALSE);
	dev->SetRenderState(D3DRS_ZWRITEENABLE, FALSE);
	dev->SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);
	dev->SetRenderState(D3DRS_LIGHTING, FALSE);
	dev->SetRenderState(D3DRS_ALPHABLENDENABLE, FALSE);
	dev->SetRenderState(D3DRS_ALPHATESTENABLE, FALSE);
	dev->SetRenderState(D3DRS_FOGENABLE, FALSE);
	dev->SetRenderState(D3DRS_STENCILENABLE, FALSE);
	dev->SetRenderState(D3DRS_SCISSORTESTENABLE, FALSE);
	dev->SetRenderState(D3DRS_COLORWRITEENABLE, 0xF);
	dev->SetTexture(0, score ? g_sbTex[0] : g_panelTex);
	dev->SetTextureStageState(0, D3DTSS_COLOROP, D3DTOP_SELECTARG1);
	dev->SetTextureStageState(0, D3DTSS_COLORARG1, D3DTA_TEXTURE);
	dev->SetTextureStageState(0, D3DTSS_ALPHAOP, D3DTOP_DISABLE);
	dev->SetTextureStageState(1, D3DTSS_COLOROP, D3DTOP_DISABLE);
	dev->SetSamplerState(0, D3DSAMP_MINFILTER, g_panelMips ? D3DTEXF_ANISOTROPIC : D3DTEXF_LINEAR);
	dev->SetSamplerState(0, D3DSAMP_MAXANISOTROPY, 8);
	dev->SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
	dev->SetSamplerState(0, D3DSAMP_MIPFILTER, g_panelMips ? D3DTEXF_LINEAR : D3DTEXF_NONE);
	dev->SetSamplerState(0, D3DSAMP_MAXMIPLEVEL, 0);
	dev->SetSamplerState(0, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
	dev->SetSamplerState(0, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
	if (key && !score && g_keyPS)
	{
		dev->SetPixelShader(g_keyPS);
		dev->SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
		dev->SetRenderState(D3DRS_SRCBLEND, D3DBLEND_SRCALPHA);
		dev->SetRenderState(D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);
		dev->SetRenderState(D3DRS_BLENDOP, D3DBLENDOP_ADD);
	}
	if (score)
	{
		// the scoreboard: colour (premultiplied) and alpha from the black/white pair, blended over the game
		bool mips = g_sbMips;
		dev->SetTexture(1, g_sbTex[1]);
		for (DWORD st = 0; st < 2; st++)
		{
			dev->SetSamplerState(st, D3DSAMP_MINFILTER, mips ? D3DTEXF_ANISOTROPIC : D3DTEXF_LINEAR);
			dev->SetSamplerState(st, D3DSAMP_MAXANISOTROPY, 8);
			dev->SetSamplerState(st, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
			dev->SetSamplerState(st, D3DSAMP_MIPFILTER, mips ? D3DTEXF_LINEAR : D3DTEXF_NONE);
			dev->SetSamplerState(st, D3DSAMP_MAXMIPLEVEL, 0);
			dev->SetSamplerState(st, D3DSAMP_ADDRESSU, D3DTADDRESS_CLAMP);
			dev->SetSamplerState(st, D3DSAMP_ADDRESSV, D3DTADDRESS_CLAMP);
		}
		dev->SetPixelShader(g_sbPS);
		dev->SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
		dev->SetRenderState(D3DRS_SRCBLEND, D3DBLEND_ONE);
		dev->SetRenderState(D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);
		dev->SetRenderState(D3DRS_BLENDOP, D3DBLENDOP_ADD);
	}
	if (SUCCEEDED(dev->BeginScene()))
	{
		// runs of columns whose edges are all in front of the eye
		for (int c0 = 0; c0 < NC; )
		{
			if (behind[c0] || behind[c0 + 1]) { c0++; continue; }
			int c1 = c0 + 1;
			while (c1 < NC && !behind[c1 + 1]) c1++;
			dev->DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2 * (c1 - c0), v + 2 * c0, sizeof(PanelVert));
			c0 = c1;
		}
		if (score) { dev->EndScene(); goto done; }
		// pointer beam and cursor: untextured, diffuse colour, opaque (not through the menu key)
		dev->SetPixelShader(nullptr);
		dev->SetRenderState(D3DRS_ALPHABLENDENABLE, FALSE);
		dev->SetTexture(0, nullptr);
		dev->SetFVF(D3DFVF_XYZRHW | D3DFVF_DIFFUSE);
		dev->SetTextureStageState(0, D3DTSS_COLOROP, D3DTOP_SELECTARG1);
		dev->SetTextureStageState(0, D3DTSS_COLORARG1, D3DTA_DIFFUSE);
		struct CV { float x, y, z, rhw; DWORD c; };
		auto proj = [&](const float* w, float& px, float& py, float& rhw) -> bool {
			float pp[3] = { w[0] - E.m[0][3], w[1] - E.m[1][3], w[2] - E.m[2][3] }, q[3];
			for (int k = 0; k < 3; k++) q[k] = E.m[0][k] * pp[0] + E.m[1][k] * pp[1] + E.m[2][k] * pp[2];
			if (q[2] > -0.02f) return false;
			px = (q[0] / -q[2] / h + 1) * 0.5f * d.Width; py = (1 - q[1] / -q[2] / h) * 0.5f * d.Height; rhw = 1.0f / -q[2];
			return true;
		};
		if (g_beamOK && g_menuCtrl)
		{
			float ax, ay, ar, bx, by, br;
			if (proj(g_beamA, ax, ay, ar) && proj(g_beamB, bx, by, br))
			{
				float dx = bx - ax, dy = by - ay, l = sqrtf(dx * dx + dy * dy); if (l < 1) l = 1;
				float nx = -dy / l * 2.0f, ny = dx / l * 2.0f;
				DWORD col = D3DCOLOR_XRGB(255, 60, 60);
				CV q[4] = { { ax + nx, ay + ny, 0, ar, col }, { ax - nx, ay - ny, 0, ar, col }, { bx + nx, by + ny, 0, br, col }, { bx - nx, by - ny, 0, br, col } };
				dev->DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, q, sizeof(CV));
			}
		}
		float cu = (g_cursorU - g_menuRect[0]) / g_menuRect[2], cvv = (g_cursorV - g_menuRect[1]) / g_menuRect[3];
		if (!g_screenMode && cu >= 0 && cu <= 1 && cvv >= 0 && cvv <= 1)
		{
			// an arrow pointer (tip on UT's cursor), white with a black outline, ~0.04 m tall on the panel
			float x = cu * 2 - 1, y = 1 - cvv * 2, w[3], px, py, pr;
			PanelPoint(x, y, w);
			if (proj(w, px, py, pr))
			{
				float u = 0.018f * pr * (d.Width * 0.5f / h) * 0.11f;   // one shape unit in pixels
				// the classic cursor outline (x right, y down, tip at 0,0), as 5 triangles
				static const float AX[7] = { 0, 0, 4, 7, 9.5f, 6.5f, 11.5f }, AY[7] = { 0, 16, 12.5f, 19, 18, 11.5f, 11.5f };
				static const int T[5][3] = { { 0, 1, 2 }, { 0, 2, 5 }, { 0, 5, 6 }, { 2, 3, 4 }, { 2, 4, 5 } };
				auto arrow = [&](float scale, DWORD col) {
					CV v[15];
					int k = 0;
					for (int t = 0; t < 5; t++)
						for (int j = 0; j < 3; j++)
						{
							int q = T[t][j];
							// grown about the arrow's middle for the outline; the tip moves out with it
							float sx = (AX[q] - 4.0f) * scale + 4.0f, sy = (AY[q] - 9.0f) * scale + 9.0f;
							v[k++] = CV{ px + sx * u, py + sy * u, 0, pr, col };
						}
					dev->DrawPrimitiveUP(D3DPT_TRIANGLELIST, 5, v, sizeof(CV));
				};
				arrow(1.22f, D3DCOLOR_XRGB(10, 10, 10));
				arrow(1.0f, D3DCOLOR_XRGB(250, 250, 250));
			}
		}
		dev->EndScene();
	}
done:
	dev->SetRenderTarget(0, oldRT); dev->SetDepthStencilSurface(oldDS);
	if (oldRT) oldRT->Release();
	if (oldDS) oldDS->Release();
	if (sb) { sb->Apply(); sb->Release(); }
	rt->Release();
}

// the right hand's ray on the panel -> OS cursor; trigger -> click (controller mode, UT in the foreground only)
static void PanelPointer(int trigger)
{
	g_beamOK = false;
	if (!g_menuCtrl || !g_rightOK) { g_oldTrig = trigger != 0; return; }
	const vr::HmdMatrix34_t& m = g_rightPose;
	float o[3] = { m.m[0][3], m.m[1][3], m.m[2][3] }, dd[3] = { -m.m[0][2], -m.m[1][2], -m.m[2][2] };
	float len = 3.0f;
	bool onPanel = false;
	float x = 0, y = 0;
	if (g_pRad > 0)
	{
		// the ray against the panel's (vertical-axis) cylinder, from inside: the far root
		float oc[3] = { o[0] - g_pO[0], o[1] - g_pO[1], o[2] - g_pO[2] };
		float du = dd[0] * g_pU[0] + dd[1] * g_pU[1] + dd[2] * g_pU[2], ou = oc[0] * g_pU[0] + oc[1] * g_pU[1] + oc[2] * g_pU[2];
		float dp[3], op[3];
		for (int k = 0; k < 3; k++) { dp[k] = dd[k] - g_pU[k] * du; op[k] = oc[k] - g_pU[k] * ou; }
		float A = dp[0] * dp[0] + dp[1] * dp[1] + dp[2] * dp[2], B = 2 * (op[0] * dp[0] + op[1] * dp[1] + op[2] * dp[2]);
		float C = op[0] * op[0] + op[1] * op[1] + op[2] * op[2] - g_pRad * g_pRad, D = B * B - 4 * A * C;
		if (A > 1e-6f && D >= 0)
		{
			float t = (-B + sqrtf(D)) / (2 * A);
			if (t > 0)
			{
				float hp[3] = { oc[0] + dd[0] * t, oc[1] + dd[1] * t, oc[2] + dd[2] * t };
				float hr = hp[0] * g_pR[0] + hp[1] * g_pR[1] + hp[2] * g_pR[2];
				float hf = -(hp[0] * g_pN[0] + hp[1] * g_pN[1] + hp[2] * g_pN[2]);
				x = atan2f(hr, hf) * g_pRad / g_pHalfW;
				y = (hp[0] * g_pU[0] + hp[1] * g_pU[1] + hp[2] * g_pU[2]) / g_pHalfH;
				onPanel = hf > 0 && fabsf(x) <= 1 && fabsf(y) <= 1;
				if (onPanel) len = t;
			}
		}
	}
	else
	{
		float den = dd[0] * g_pN[0] + dd[1] * g_pN[1] + dd[2] * g_pN[2];
		if (den < -1e-4f)
		{
			float t = ((g_pC[0] - o[0]) * g_pN[0] + (g_pC[1] - o[1]) * g_pN[1] + (g_pC[2] - o[2]) * g_pN[2]) / den;
			if (t > 0)
			{
				float hit[3] = { o[0] + dd[0] * t - g_pC[0], o[1] + dd[1] * t - g_pC[1], o[2] + dd[2] * t - g_pC[2] };
				x = (hit[0] * g_pR[0] + hit[1] * g_pR[1] + hit[2] * g_pR[2]) / g_pHalfW;
				y = (hit[0] * g_pU[0] + hit[1] * g_pU[1] + hit[2] * g_pU[2]) / g_pHalfH;
				onPanel = fabsf(x) <= 1 && fabsf(y) <= 1;
				if (onPanel) len = t;
			}
		}
	}
	for (int k = 0; k < 3; k++) { g_beamA[k] = o[k]; g_beamB[k] = o[k] + dd[k] * len; }
	g_beamOK = true;
	HWND root = g_hwnd ? GetAncestor(g_hwnd, GA_ROOT) : nullptr;
	bool fg = root && GetForegroundWindow() == root;
	if (onPanel)
	{
		// UT reads the mouse through DirectInput, so the game moves its menu cursor itself (GUIController.MouseX/Y)
		float u = (x + 1) * 0.5f, v = (1 - y) * 0.5f;
		Send("U %.4f %.4f", g_menuRect[0] + u * g_menuRect[2], g_menuRect[1] + v * g_menuRect[3]);
		// the click itself is done by the game (it calls the control's OnClick); injected mouse clicks never reached UT
	}
	g_oldTrig = trigger != 0;
}

// debug: write a 1/4-size BMP of a locked eye target (frame 400, DumpEyes=1)
static void DumpBMP(const char* name, const D3DLOCKED_RECT& lr, UINT size)
{
	UINT w = size / 4;
	std::string p = g_dir + name;
	FILE* f = fopen(p.c_str(), "wb");
	if (!f) return;
	BITMAPFILEHEADER fh = {}; BITMAPINFOHEADER ih = {};
	ih.biSize = sizeof ih; ih.biWidth = w; ih.biHeight = -(LONG)w; ih.biPlanes = 1; ih.biBitCount = 32;
	fh.bfType = 0x4D42; fh.bfOffBits = sizeof fh + sizeof ih; fh.bfSize = fh.bfOffBits + w * w * 4;
	fwrite(&fh, sizeof fh, 1, f); fwrite(&ih, sizeof ih, 1, f);
	for (UINT y = 0; y < w; y++)
		for (UINT x = 0; x < w; x++)
		{
			const unsigned char* px = (const unsigned char*)lr.pBits + lr.Pitch * (y * 4) + (x * 4) * 4;
			unsigned char c[4] = { px[0], px[1], px[2], 255 };
			fwrite(c, 4, 1, f);
		}
	fclose(f);
	Log("dumped %s (corner pixel BGRA %d %d %d %d, centre alpha %d)", name,
		((unsigned char*)lr.pBits)[0], ((unsigned char*)lr.pBits)[1], ((unsigned char*)lr.pBits)[2], ((unsigned char*)lr.pBits)[3],
		((const unsigned char*)lr.pBits + lr.Pitch * (size / 2) + (size / 2) * 4)[3]);
}

// Copy one eye (what the headset shows of it, i.e. the cropped frustum) into the desktop window's backbuffer, so the
// UT2004 window - and a recording of it - shows the headset view with HUD, gun and everything.
static void MirrorToWindow(IDirect3DDevice9* dev, IDirect3DTexture9* eyeTex, int e)
{
	if (!eyeTex) return;
	IDirect3DSurface9* src = nullptr;
	IDirect3DSurface9* bb = nullptr;
	if (FAILED(eyeTex->GetSurfaceLevel(0, &src)) || !src) return;
	if (FAILED(dev->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &bb)) || !bb) { src->Release(); return; }
	D3DSURFACE_DESC sd, bd;
	src->GetDesc(&sd);
	bb->GetDesc(&bd);
	const float PI = 3.14159265f;
	float h = tanf(g_fov * 0.5f * PI / 180.0f);
	// The eye's frustum is asymmetric (the outer side reaches further, e.g. left eye l=-1.21 r=0.85), so a mirror of
	// its whole visible area is off-centre. Use the largest region symmetric around straight ahead (texture centre),
	// so the HUD is centred and shots land in the middle of the picture.
	float hx = std::min(h, std::min(-g_tan[e][0], g_tan[e][1]) * g_mirrorZoom);   // half-width, in tangents
	float vy = std::min(h, std::min(-g_tan[e][2], g_tan[e][3]) * g_mirrorZoom);   // half-height
	float dstAspect = (float)bd.Width / bd.Height;
	RECT dr = { 0, 0, (LONG)bd.Width, (LONG)bd.Height };
	if (g_mirrorFill)
	{
		if (hx / vy > dstAspect) hx = vy * dstAspect; else vy = hx / dstAspect;   // crop to the window shape
	}
	else
	{
		dev->ColorFill(bb, nullptr, D3DCOLOR_XRGB(0, 0, 0));                      // letterbox
		if (hx / vy > dstAspect) { LONG hh = (LONG)(bd.Width * vy / hx); dr.top = (bd.Height - hh) / 2; dr.bottom = dr.top + hh; }
		else { LONG ww = (LONG)(bd.Height * hx / vy); dr.left = (bd.Width - ww) / 2; dr.right = dr.left + ww; }
	}
	float px = sd.Width * 0.5f / h;   // pixels per tangent
	// centre on the head's forward (where the HUD and a level aim are centred), not the eye's own axis: real
	// headsets angle the eyes slightly relative to the head
	float cx = sd.Width * 0.5f + g_headFwdTan[e][0] * px, cy = sd.Height * 0.5f - g_headFwdTan[e][1] * px;
	float sx0 = cx - hx * px, sx1 = cx + hx * px, sy0 = cy - vy * px, sy1 = cy + vy * px;
	RECT sr = { (LONG)sx0, (LONG)sy0, (LONG)sx1, (LONG)sy1 };
	HRESULT hr = dev->StretchRect(src, &sr, bb, &dr, D3DTEXF_LINEAR);
	static bool logged = false;
	if (!logged) { Log("mirror eye %d -> window %ux%u (src %ld,%ld-%ld,%ld) -> %08x", e, bd.Width, bd.Height, sr.left, sr.top, sr.right, sr.bottom, hr); logged = true; }
	src->Release();
	bb->Release();
}

static void ReleaseOwnEyes()
{
	for (int e = 0; e < 2; e++)
	{
		if (g_ownEye[e]) { g_ownEye[e]->Release(); g_ownEye[e] = nullptr; }
		if (g_own11[e]) { g_own11[e]->Release(); g_own11[e] = nullptr; }
		g_ownShare[e] = nullptr;
	}
	g_ownSize = 0;
}

// the standalone view's eye targets: square, not the game's eye size (so the CreateTexture hook doesn't take them
// for the game's eyes), cleared to a dark grey each frame
static bool EnsureOwnEyes(IDirect3DDevice9* dev)
{
	UINT size = (g_eyeW == 1536) ? 1600 : 1536;
	if (g_ownEye[0] && g_ownEye[1] && g_ownSize == size) return true;
	ReleaseOwnEyes();
	for (int e = 0; e < 2; e++)
	{
		HANDLE sh = nullptr;
		HRESULT hr = dev->CreateTexture(size, size, 1, D3DUSAGE_RENDERTARGET, D3DFMT_A8R8G8B8, D3DPOOL_DEFAULT, &g_ownEye[e], g_isEx ? &sh : nullptr);
		if (FAILED(hr)) { Log("standalone eye target %u failed %08x", size, hr); ReleaseOwnEyes(); return false; }
		g_ownShare[e] = sh;
	}
	g_ownSize = size;
	Log("standalone eye targets %ux%u shared %p %p", size, size, g_ownShare[0], g_ownShare[1]);
	return true;
}

static void ClearOwnEyes(IDirect3DDevice9* dev)
{
	for (int e = 0; e < 2; e++)
	{
		IDirect3DSurface9* s = nullptr;
		if (SUCCEEDED(g_ownEye[e]->GetSurfaceLevel(0, &s)) && s)
		{
			dev->ColorFill(s, nullptr, D3DCOLOR_XRGB(16, 18, 22));
			s->Release();
		}
	}
}

static void SubmitFrame(IDirect3DDevice9* dev)
{
	// classify new targets
	for (int i = 0; i < g_nCand; i++)
	{
		if (g_cand[i].eye >= 0 || g_cand[i].tries > 30) continue;
		g_cand[i].tries++;
		D3DLOCKED_RECT lr; UINT size;
		int e = ReadTarget(dev, g_cand[i].tex, lr, size);
		if (e != -2) g_sysmem->UnlockRect();
		if (e >= 0)
		{
			// the newest target with this tag wins; drop older ones for the same eye
			// (for good: the old ones stay alive and keep their tags, e.g. the intro's after a game starts, and
			// re-classifying them made the eyes flip between the two pairs and end on the stale one)
			for (int j = 0; j < g_nCand; j++) if (j != i && g_cand[j].eye == e) { g_cand[j].eye = -3; g_cand[j].tries = 1000; }
			g_cand[i].eye = e;
			Log("eye %d render target %p (%ux%u) t=%.0f", e, g_cand[i].tex, size, size, Now());
			g_eyesStale = false;
		}
	}
	int eyeIdx[2] = { -1, -1 };
	for (int i = 0; i < g_nCand; i++) if (g_cand[i].eye == 0 || g_cand[i].eye == 1) eyeIdx[g_cand[i].eye] = i;
	PollGame();
	bool haveEyes = eyeIdx[0] >= 0 && eyeIdx[1] >= 0;
	// eyes from before the menus (the intro's, the last level's) aren't this game's: wait for the new ones; if none
	// turn up while the game runs (the engine reused the targets), take them after 1.5 s
	if (g_eyesStale && haveEyes && g_vrGameAt > 0 && Now() - g_vrSince > 1500)
	{
		Log("no new eye targets after 1.5 s of a VR game: using the known ones t=%.0f", Now());
		g_eyesStale = false;
	}
	if (g_eyesStale) haveEyes = false;
	bool standalone = Now() < g_standaloneUntil;
	// a VR game says its eyes render: show them now, not when the menus' standalone view times out (that gap showed
	// the loading screen and the first frames on the flat big screen)
	if (standalone && haveEyes && Now() - g_vrGameAt < 1000)
	{
		Log("VR game eyes up: leaving the standalone view t=%.0f", Now());
		g_standaloneUntil = 0;
		standalone = false;
	}
	// nothing to show yet (a level loading, eyes not found yet), or eyes that no VR game is announcing any more
	// (left over from the last level while the next one loads - stale or half-overwritten frames): the dark room
	// (also before any "M 0": during a level load after the menus none comes, and the last known eyes showed)
	if (!standalone && (!haveEyes || g_vrGameAt == 0 || Now() - g_vrGameAt > 2000)) standalone = true;

	// the two eye targets this frame: the game's, or (standalone) our own dark room
	IDirect3DTexture9* eyeTex[2];
	HANDLE* eyeShare[2];
	ID3D11Texture2D** eye11[2];
	if (standalone)
	{
		if (!EnsureOwnEyes(dev)) return;
		ClearOwnEyes(dev);
		for (int e = 0; e < 2; e++) { eyeTex[e] = g_ownEye[e]; eyeShare[e] = &g_ownShare[e]; eye11[e] = &g_own11[e]; }
	}
	else
		for (int e = 0; e < 2; e++) { Candidate& c = g_cand[eyeIdx[e]]; eyeTex[e] = c.tex; eyeShare[e] = &c.share; eye11[e] = &c.tex11; }

	bool screen = standalone && !g_menuOpen && g_standaloneScreen && Now() < g_standaloneUntil;
	if (screen != g_screenMode)
	{
		g_screenMode = screen;
		g_panelPlaced = false;
		if (screen) Log("no VR game and no menu: the window on a big screen t=%.0f", Now());
	}
	if ((g_menuOpen || g_screenMode) && (g_havePose || g_mock))
	{
		if (g_panelPlaced && standalone && g_worn && g_followDeg > 0)
		{
			// the main menus, PanelFollowDeg set: look away from the panel that far for 1.5 s and it comes back in
			// front of you. Off by default: the panel faces the seated calibration (and is placed again when the
			// headset goes on), and a following panel was gone when you looked back (user: "turn ~40 deg, it disappears")
			static double awaySince = 0;
			const vr::HmdMatrix34_t& m = g_renderPose;
			float fx = -m.m[0][2], fz = -m.m[2][2], l = sqrtf(fx * fx + fz * fz);
			float dot = l > 1e-3f ? (fx * -g_pN[0] + fz * -g_pN[2]) / l : 1.0f;
			if (dot < cosf(g_followDeg * 3.14159265f / 180.0f)) { if (awaySince == 0) awaySince = Now(); else if (Now() - awaySince > 1500) { g_panelPlaced = false; g_panelRecentred = true; awaySince = 0; } }
			else awaySince = 0;
		}
		// placed while the headset lay on the desk: once you put it on, again in front of your head
		if (g_panelPlaced && g_panelSeated && !g_panelSeatedWorn && g_worn) g_panelPlaced = false;
		if (!g_panelPlaced) PlacePanel(standalone && !g_panelRecentred);
		g_panelRecentred = false;
		// in a game the menu is on black (VRHUD): key it out; so is a dialog drawn alone; the main menus' own
		// backdrop stays
		bool key = (!standalone || g_menuDialog) && !g_screenMode;
		if (key) KeyShader(dev);
		if (CapturePanel(dev))
		{
			DrawPanelInEye(dev, eyeTex[0], 0, false, key);
			DrawPanelInEye(dev, eyeTex[1], 1, false, key);
		}
	}
	// UT's scoreboard / spectator bar: placed in front of you when it comes up, and stays there in the room while it is up
	if (g_menuOpen || g_screenMode) g_sbPlaced = false;
	else if (!standalone && ScoreUp() && g_sbHave[0] && g_sbHave[1] && g_sbPS && (g_havePose || g_mock))
	{
		if (g_sbKind == 3)
		{
			// the game type's HUD: in front of the head every frame, flat, where the VR HUD's corners would be (the
			// pose this frame was rendered with, so it never lags the eyes)
			const vr::HmdMatrix34_t& m = g_renderPose;
			for (int k = 0; k < 3; k++)
			{
				g_pR[k] = m.m[k][0]; g_pU[k] = m.m[k][1]; g_pN[k] = m.m[k][2];   // +Z points back at the viewer
				g_pC[k] = m.m[k][3] - m.m[k][2] * g_hlDist + m.m[k][1] * g_hlUp;
			}
			g_pRad = 0;
			g_pHalfW = g_hlHalfW;
			g_sbPlaced = false;
		}
		else if (!g_sbPlaced) { g_placingScore = true; PlacePanel(false); g_placingScore = false; g_panelPlaced = false; g_sbPlaced = true; }
		if (g_sbKind != 3) g_pHalfW = (g_sbKind == 2 ? g_specWidth : g_sbWidth) * 0.5f;
		g_pHalfH = g_pHalfW * (1 - g_sbTop) * g_sbH / std::max(1u, g_sbW);
		DrawPanelInEye(dev, eyeTex[0], 0, true);
		DrawPanelInEye(dev, eyeTex[1], 1, true);
	}
	else if (!ScoreUp()) g_sbPlaced = false;

	ID3D11Texture2D* submitTex[2] = {};
	bool shared = g_isEx && *eyeShare[0] && *eyeShare[1];
	if (shared)
	{
		// zero-copy: D3D11 opens the engine's own render targets. Fence D3D9 first so the compositor
		// never samples a half-drawn eye.
		double t0 = Now();
		if (!Ensure11(0)) return;
		for (int e = 0; e < 2; e++)
		{
			if (!*eye11[e])
			{
				HRESULT hr = g_d11->OpenSharedResource(*eyeShare[e], __uuidof(ID3D11Texture2D), (void**)eye11[e]);
				Log("eye %d: OpenSharedResource -> %08x", e, hr);
				if (FAILED(hr)) { *eyeShare[e] = nullptr; return; }
			}
			submitTex[e] = *eye11[e];
		}
		static IDirect3DQuery9* q = nullptr;
		static IDirect3DDevice9* qdev = nullptr;
		if (qdev != dev) { if (q) q->Release(); q = nullptr; qdev = dev; dev->CreateQuery(D3DQUERYTYPE_EVENT, &q); }
		if (q)
		{
			q->Issue(D3DISSUE_END);
			while (q->GetData(nullptr, 0, D3DGETDATA_FLUSH) == S_FALSE) SwitchToThread();
		}
		g_tRead += Now() - t0;
		if (g_dumpEyes && g_frames >= 400 && (g_frames - 400) % 300 == 0 && g_frames <= 400 + 300 * 11)
		{
			// read back what D3D11 actually sees through the share
			for (int e = 0; e < 2; e++)
			{
				D3D11_TEXTURE2D_DESC d;
				submitTex[e]->GetDesc(&d);
				d.Usage = D3D11_USAGE_STAGING; d.BindFlags = 0; d.CPUAccessFlags = D3D11_CPU_ACCESS_READ; d.MiscFlags = 0;
				ID3D11Texture2D* st = nullptr;
				if (SUCCEEDED(g_d11->CreateTexture2D(&d, nullptr, &st)))
				{
					g_ctx->CopyResource(st, submitTex[e]);
					D3D11_MAPPED_SUBRESOURCE m;
					if (SUCCEEDED(g_ctx->Map(st, 0, D3D11_MAP_READ, 0, &m)))
					{
						D3DLOCKED_RECT lr; lr.pBits = m.pData; lr.Pitch = (INT)m.RowPitch;
						char nm[64];
						if (g_frames == 400) snprintf(nm, sizeof nm, "UT2004VR_eye%d.bmp", e);
						else snprintf(nm, sizeof nm, "UT2004VR_eye%d_%02u.bmp", e, (g_frames - 400) / 300);
						DumpBMP(nm, lr, d.Width);
						g_ctx->Unmap(st, 0);
					}
					st->Release();
				}
			}
		}
	}
	else
	{
		for (int e = 0; e < 2; e++)
		{
			D3DLOCKED_RECT lr; UINT size;
			double t0 = Now();
			if (ReadTarget(dev, eyeTex[e], lr, size) == -2) return;
			double t1 = Now();
			g_tRead += t1 - t0;
			if (!Ensure11(size)) { g_sysmem->UnlockRect(); return; }
			g_ctx->UpdateSubresource(g_eye11[e], 0, nullptr, lr.pBits, lr.Pitch, 0);
			g_tUpload += Now() - t1;
			if (g_dumpEyes && g_frames == 400) DumpBMP(e ? "UT2004VR_eye1.bmp" : "UT2004VR_eye0.bmp", lr, size);
			g_sysmem->UnlockRect();
			submitTex[e] = g_eye11[e];
		}
	}
	static int lastMode = -1;
	if ((int)shared != lastMode) { Log("eye transfer: %s", shared ? "GPU shared (D3D9Ex)" : "CPU readback"); lastMode = shared; }
	if (!g_hmd) return;
	double ts = Now();

	// square target, square pixels: tangent x maps to u = (x/h + 1)/2, same for y
	const float PI = 3.14159265f;
	float h = tanf(g_fov * 0.5f * PI / 180.0f);
	for (int e = 0; e < 2; e++)
	{
		vr::VRTextureBounds_t bounds;
		bounds.uMin = (g_tan[e][0] / h + 1) * 0.5f;
		bounds.uMax = (g_tan[e][1] / h + 1) * 0.5f;
		bounds.vMin = (g_tan[e][2] / h + 1) * 0.5f;
		bounds.vMax = (g_tan[e][3] / h + 1) * 0.5f;
		vr::VRTextureWithPose_t tex = {};
		tex.handle = submitTex[e];
		tex.eType = vr::TextureType_DirectX;
		tex.eColorSpace = vr::ColorSpace_Gamma;
		tex.mDeviceToAbsoluteTracking = g_renderPose;
		vr::EVRCompositorError ce = vr::VRCompositor()->Submit((vr::EVREye)e, &tex, &bounds,
			g_havePose ? vr::Submit_TextureWithPose : vr::Submit_Default);
		static int errs = 0;
		if (ce != vr::VRCompositorError_None && (errs++ < 20 || g_frames % 600 == 0)) Log("Submit eye %d error %d (frame %u)", e, ce, g_frames);
	}
	vr::VRCompositor()->PostPresentHandoff();
	g_tSubmit += Now() - ts;
}

static void SendStatic()
{
	vr::HmdMatrix34_t sm;
	if (SeatedPose(sm))
	{
		// the seated calibration: the intro's camera anchors on it, not on the headset's pose at startup
		V3 p, f, u;
		PoseVectors(sm, p, f, u);
		SendPose('Z', 0, p, f, u);
	}
	if (g_hmd)
	{
		for (int e = 0; e < 2; e++)
		{
			V3 p, f, u;
			PoseVectors(g_hmd->GetEyeToHeadTransform((vr::EVREye)e), p, f, u);
			Send("E %d %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f", e, p.x, p.y, p.z, f.x, f.y, f.z, u.x, u.y, u.z);
		}
	}
	else
	{
		Send("E 0 0 -0.032 0 1 0 0 0 0 1");
		Send("E 1 0 0.032 0 1 0 0 0 0 1");
	}
	Send("C %d %d %d", g_fov, g_eyeW, g_eyeH);
	// the window mirror is drawn by the game (VRHUD) under the console/menus: tell it which eye and how much
	{
		int e = (g_mirrorEye == 1) ? 1 : 0;
		float hx = std::min(-g_tan[e][0], g_tan[e][1]) * g_mirrorZoom, vy = std::min(-g_tan[e][2], g_tan[e][3]) * g_mirrorZoom;
		if (g_tan[e][1] == 0) { hx = 0.85f * g_mirrorZoom; vy = 0.95f * g_mirrorZoom; }
		Send("K %d %.4f %.4f", (g_mirrorEye == 0 || g_mirrorEye == 1) ? g_mirrorEye : -1, hx, vy);
	}
}

static void SendHand(char tag, vr::VRActionHandle_t a)
{
	vr::InputPoseActionData_t pd = {};
	bool ok = g_input && vr::VRInput()->GetPoseActionDataForNextFrame(a, vr::TrackingUniverseStanding, &pd, sizeof pd, vr::k_ulInvalidInputValueHandle) == vr::VRInputError_None
		&& pd.bActive && pd.pose.bPoseIsValid;
	V3 p{}, f{ 1, 0, 0 }, u{ 0, 0, 1 };
	if (ok) PoseVectors(pd.pose.mDeviceToAbsoluteTracking, p, f, u);
	if (tag == 'R') { g_rightOK = ok; if (ok) g_rightPose = pd.pose.mDeviceToAbsoluteTracking; }
	SendPose(tag, ok ? 1 : 0, p, f, u);
}

static float Vec2(vr::VRActionHandle_t a, float& y)
{
	vr::InputAnalogActionData_t d = {};
	y = 0;
	if (!g_input || vr::VRInput()->GetAnalogActionData(a, &d, sizeof d, vr::k_ulInvalidInputValueHandle) != vr::VRInputError_None || !d.bActive) return 0;
	y = d.y;
	return d.x;
}

static int Btn(vr::VRActionHandle_t a)
{
	vr::InputDigitalActionData_t d = {};
	if (!g_input || vr::VRInput()->GetDigitalActionData(a, &d, sizeof d, vr::k_ulInvalidInputValueHandle) != vr::VRInputError_None) return 0;
	return d.bActive && d.bState ? 1 : 0;
}

// after Present: wait for the headset, then tell the game where the head will be
static void AfterPresent(UINT bbW, UINT bbH)
{
	g_frames++;
	if (g_mock)
	{
		// pace like a 90 Hz headset would (WaitGetPoses does this in VR)
		static LARGE_INTEGER freq, next;
		LARGE_INTEGER now;
		if (!freq.QuadPart) QueryPerformanceFrequency(&freq);
		QueryPerformanceCounter(&now);
		if (next.QuadPart > now.QuadPart)
		{
			DWORD ms = (DWORD)((next.QuadPart - now.QuadPart) * 1000 / freq.QuadPart);
			if (ms > 0) Sleep(ms);
		}
		else next = now;
		next.QuadPart += freq.QuadPart / 90;
		if (g_frames % 900 == 0)
		{
			Log("mock timing per frame (ms): readback %.2f, upload %.2f", g_tRead / 900, g_tUpload / 900);
			g_tRead = g_tUpload = 0;
		}
		if (g_eyeW == 0)
		{
			// emulate the user's headset (tangents and 2624x2572 recommended size from their log)
			const float T[2][4] = { { -1.2136f, 0.8466f, -0.9966f, 1.0194f }, { -0.8466f, 1.2136f, -0.9966f, 1.0194f } };
			memcpy(g_tan, T, sizeof T);
			SetEyeTargets(1.2136f, 1.0194f, 2624 / (0.8466f + 1.2136f));
			Log("mock: fov %d, eye render targets %dx%d", g_fov, g_eyeW, g_eyeH);
		}
		float t = GetTickCount() / 1000.0f;
		float yaw = g_mockDemo2 ? 0.0f : 0.35f * sinf(t * 0.5f);
		V3 p{ 0, 0, 1.70f }, f{ cosf(yaw), sinf(yaw), 0 }, u{ 0, 0, 1 };
		if (g_mockSeated) p.z = g_frames < 1500 ? 1.10f : 1.30f;   // MockDemo=5: seated, sits up 20 cm after ~17 s
		if (g_mockLookAway)
		{
			g_worn = true;
			float ya = (g_frames < 2200 ? 0.0f : g_frames < 3000 ? 40.0f : 55.0f) * 3.14159265f / 180.0f;
			f = V3{ cosf(ya), sinf(ya), 0 };
		}
		if (g_mockHeading && g_frames >= 300) { float y6 = 60.0f * 3.14159265f / 180.0f; f = V3{ cosf(y6), sinf(y6), 0 }; }
		if (g_mockPitchRoll)
		{
			// head pitched up 20 deg, rolled 15 deg (right ear down), built in OpenVR space and converted
			// exactly like a real pose, to test the whole rotation chain
			float pa = 20 * 3.14159265f / 180, ra = 15 * 3.14159265f / 180;
			// OpenVR: forward -Z, up +Y, right +X. pitch about +X, then roll about the new forward
			float fx = 0, fy = sinf(pa), fz = -cosf(pa);
			float ux0 = 0, uy0 = cosf(pa), uz0 = sinf(pa);
			float rx = 1, ry = 0, rz = 0;
			// roll right-ear-down: up tilts toward +right
			float ux = ux0 * cosf(ra) + rx * sinf(ra), uy = uy0 * cosf(ra) + ry * sinf(ra), uz = uz0 * cosf(ra) + rz * sinf(ra);
			f = ToUE(fx, fy, fz);
			u = ToUE(ux, uy, uz);
		}
		// MockDemo=1: a 16 s loop that exercises smooth move, snap turn, teleport and jump
		float mx = 0, my = 0, tx = 0, ty = 0;
		int jump = 0;
		if (g_mockDemo)
		{
			float c = fmodf(t, 16.0f);
			if (c >= 2 && c < 5) my = 1.0f;              // walk forward
			else if (c >= 5.5f && c < 5.8f) tx = 1.0f;   // snap right
			else if (c >= 6.5f && c < 6.8f) tx = -1.0f;  // snap left
			else if (c >= 8 && c < 10) ty = 1.0f;        // aim teleport ...
			else if (c >= 11 && c < 13) mx = 1.0f;       // ... released at 10 s; strafe right
			else if (c >= 14 && c < 14.2f) jump = 1;
			yaw = 0;
			f = V3{ 1, 0, 0 };
		}
		Send("H %d %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f 1", (int)++g_seq, p.x, p.y, p.z, f.x, f.y, f.z, u.x, u.y, u.z);
		// the same mock head as an OpenVR pose (x right, y up, -z forward), for the menu panel
		{
			float F[3] = { f.y, f.z, -f.x }, U[3] = { u.y, u.z, -u.x };
			float Rr[3] = { F[1] * U[2] - F[2] * U[1], F[2] * U[0] - F[0] * U[2], F[0] * U[1] - F[1] * U[0] };
			for (int r = 0; r < 3; r++) { g_renderPose.m[r][0] = Rr[r]; g_renderPose.m[r][1] = U[r]; g_renderPose.m[r][2] = -F[r]; }
			g_renderPose.m[0][3] = p.y; g_renderPose.m[1][3] = p.z; g_renderPose.m[2][3] = -p.x;
		}
		Send("L 0 0 0 0 1 0 0 0 0 1");
		if (g_mockCrouch)
		{
			unsigned f8 = g_frames;
			// walk 300-1200; hold crouch 500-900; jump with the stick centred at 1300; hold crouch 1500-1800 and
			// jump at 1600 (stands up, then jumps); a jump at 1100 while walking is ignored (stick pushed)
			float fw = (f8 >= 300 && f8 < 1200) ? 1.0f : 0.0f;
			int cr = ((f8 >= 500 && f8 < 900) || (f8 >= 1500 && f8 < 1800)) ? 1 : 0;
			int jp = ((f8 >= 1100 && f8 < 1104) || (f8 >= 1300 && f8 < 1304) || (f8 >= 1600 && f8 < 1604)) ? 1 : 0;
			Send("I 0 %.1f 0 0 %d %d 0 0 0 0 0 0 0", fw, jp, cr);
		}
		else if (g_mockJump)
		{
			int j = ((g_frames >= 600 && g_frames < 604) || (g_frames >= 632 && g_frames < 636)) ? 1 : 0;
			Send("R 0 0 0 0 1 0 0 0 0 1");
			Send("I 0 0 0 0 %d 0 0 0 0 0 0 0 0", j);
		}
		else if (g_mockHeading)
		{
			float fw = (g_frames >= 600 && g_frames < 1050) ? 1.0f : ((g_frames >= 1050 && g_frames < 1500) ? -1.0f : 0.0f);   // forward, then backward
			// left trigger dodges toward the stick: strafe left + dodge at 1700, right at 2000, centred (ignored) at 2200;
			// left X toggles the scoreboard at 2300 and 2600
			float mx = (g_frames >= 1690 && g_frames < 1710) ? -1.0f : ((g_frames >= 1990 && g_frames < 2010) ? 1.0f : 0.0f);
			int dg = ((g_frames >= 1700 && g_frames < 1705) || (g_frames >= 2000 && g_frames < 2005) || (g_frames >= 2200 && g_frames < 2205)) ? 1 : 0;
			int sc = ((g_frames >= 2300 && g_frames < 2305) || (g_frames >= 2600 && g_frames < 2605)) ? 1 : 0;
			Send("R 0 0 0 0 1 0 0 0 0 1");
			Send("I %.1f %.1f 0 0 0 0 0 0 0 0 0 %d %d", mx, fw, dg, sc);
		}
		else if (g_mockGun)
		{
			// MockDemo=4: right hand held out in front at chest height, aiming 10 deg right and 5 deg down;
			// fire around frame 390 (so DumpEyes at 400 catches the beam), alt-fire around 690
			// roll the wrist +-57 deg around the aim axis (forward stays put)
			float ra = sinf(t * 1.3f) * 1.05f;   // roll the wrist +-60 deg
			V3 fw{ 0.9811f, 0.1730f, -0.0872f }, up0{ 0.0858f, 0.0151f, 0.9962f };
			V3 rt{ up0.y * fw.z - up0.z * fw.y, up0.z * fw.x - up0.x * fw.z, up0.x * fw.y - up0.y * fw.x };
			V3 up{ up0.x * cosf(ra) + rt.x * sinf(ra), up0.y * cosf(ra) + rt.y * sinf(ra), up0.z * cosf(ra) + rt.z * sinf(ra) };
			Send("R 1 0.35 0.18 1.30 %.4f %.4f %.4f %.4f %.4f %.4f", fw.x, fw.y, fw.z, up.x, up.y, up.z);
			int fire = (g_frames >= 385 && (g_frames - 385) % 300 < 7) ? 1 : 0;   // fire before each dump
			int alt = (g_frames >= 440 && (g_frames - 440) % 300 < 25) ? 1 : 0;   // then a short alt-fire
			int next = (g_frames >= 500 && (g_frames - 500) % 300 < 5) ? 1 : 0;   // next weapon between dumps
			float walk = (g_frames >= 100 && g_frames < 300) ? 1.0f : 0.0f;   // walk away from the spawn point first
			Send("I 0 %.1f 0 0 0 0 0 %d %d %d 0", walk, fire, alt, next);
		}
		else
		{
			Send("R 1 0.2 0.25 1.2 0.8 0 0.6 -0.6 0 0.8");
			Send("I %.2f %.2f %.2f %.2f %d 0 0 0 0 0 0", mx, my, tx, ty, jump);
		}
		if (g_frames % 60 == 1) SendStatic();
		return;
	}
	static double lastEnd = 0;
	double tw = Now();
	if (lastEnd > 0) g_tGame += tw - lastEnd;   // includes this frame's submit/readback
	vr::EVRCompositorError we = vr::VRCompositor()->WaitGetPoses(g_poses, vr::k_unMaxTrackedDeviceCount, nullptr, 0);
	lastEnd = Now();
	g_tWait += lastEnd - tw;
	if (g_frames % 900 == 0)
	{
		Log("timing per frame (ms): game+render %.2f (of which readback %.2f, upload %.2f, submit %.2f), WaitGetPoses %.2f",
			g_tGame / 900, g_tRead / 900, g_tUpload / 900, g_tSubmit / 900, g_tWait / 900);
		g_tGame = g_tRead = g_tUpload = g_tSubmit = g_tWait = 0;
	}
	if (we == vr::VRCompositorError_None) g_waited = true;
	else if (g_frames < 20 || g_frames % 600 == 0) Log("WaitGetPoses error %d", we);
	const vr::TrackedDevicePose_t& hp = g_poses[vr::k_unTrackedDeviceIndex_Hmd];
	if (hp.bPoseIsValid)
	{
		g_renderPose = hp.mDeviceToAbsoluteTracking;
		g_havePose = true;
		V3 p, f, u;
		PoseVectors(g_renderPose, p, f, u);
		// worn = proximity sensor / user interaction (some drivers only report Idle; then assume worn once it moves)
		vr::EDeviceActivityLevel act = g_hmd->GetTrackedDeviceActivityLevel(vr::k_unTrackedDeviceIndex_Hmd);
		int worn = (act == vr::k_EDeviceActivityLevel_UserInteraction || act == vr::k_EDeviceActivityLevel_UserInteraction_Timeout) ? 1 : 0;
		static bool sawWorn = false;
		if (worn) sawWorn = true;
		if (!sawWorn && g_frames > 270) worn = 1;   // driver without a proximity sensor: assume worn after ~3 s
		static int lastAct = -1;
		if ((int)act != lastAct) { Log("HMD activity level %d (worn=%d), head height %.2f m", (int)act, worn, p.z); lastAct = (int)act; }
		// the tracking state (200 running, 300 rotation only: WMR loses its cameras' fix and the position freezes)
		static int lastTrack = -1;
		int track = (int)hp.eTrackingResult;
		if (track != lastTrack) { Log("HMD tracking %s (%d) t=%.0f", track == vr::TrackingResult_Running_OK ? "6DoF" : track == vr::TrackingResult_Fallback_RotationOnly ? "rotation only" : "other", track, Now()); lastTrack = track; }
		Send("H %d %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %d %d", (int)++g_seq, p.x, p.y, p.z, f.x, f.y, f.z, u.x, u.y, u.z, worn, track);
		// on the head it always moves a little; on the desk it is perfectly still (WMR reports "worn" there too)
		static V3 mp = {}, mf = {};
		static double movedAt = 0, refAt = 0;
		if (Now() - refAt > 500)
		{
			float dp = sqrtf((p.x - mp.x) * (p.x - mp.x) + (p.y - mp.y) * (p.y - mp.y) + (p.z - mp.z) * (p.z - mp.z));
			float df = f.x * mf.x + f.y * mf.y + f.z * mf.z;
			if (dp > 0.003f || df < 0.99995f) movedAt = Now();
			mp = p; mf = f; refAt = Now();
		}
		bool wornNow = worn != 0 && Now() - movedAt < 1500;
		if (wornNow != g_worn) Log("headset %s t=%.0f", wornNow ? "on (worn and moving)" : "off or still", Now());
		g_worn = wornNow;
	}
	if (g_input)
	{
		vr::VRActiveActionSet_t as = {};
		as.ulActionSet = g_set;
		vr::VRInput()->UpdateActionState(&as, sizeof as, 1);
	}
	SendHand('L', g_aPoseL);
	SendHand('R', g_aPoseR);
	float my, ty;
	float mx = Vec2(g_aMove, my);
	float tx = Vec2(g_aTurn, ty);
	if (g_menuOpen && g_panelPlaced) PanelPointer(Btn(g_aFire));
	Send("I %.3f %.3f %.3f %.3f %d %d %d %d %d %d %d %d %d", mx, my, tx, ty, Btn(g_aJump), Btn(g_aCrouch), Btn(g_aMenu),
		Btn(g_aFire), Btn(g_aAlt), Btn(g_aNext), Btn(g_aPrev), Btn(g_aDodge), Btn(g_aScores));
	if (g_frames % 60 == 1) SendStatic();
}

// ---------------------------------------------------------------------------
// vtable hooks
// ---------------------------------------------------------------------------
typedef HRESULT(STDMETHODCALLTYPE* PFN_Present)(IDirect3DDevice9*, const RECT*, const RECT*, HWND, const RGNDATA*);
typedef HRESULT(STDMETHODCALLTYPE* PFN_Reset)(IDirect3DDevice9*, D3DPRESENT_PARAMETERS*);
typedef HRESULT(STDMETHODCALLTYPE* PFN_SCPresent)(IDirect3DSwapChain9*, const RECT*, const RECT*, HWND, const RGNDATA*, DWORD);
typedef HRESULT(STDMETHODCALLTYPE* PFN_CreateTexture)(IDirect3DDevice9*, UINT, UINT, UINT, DWORD, D3DFORMAT, D3DPOOL, IDirect3DTexture9**, HANDLE*);
typedef HRESULT(STDMETHODCALLTYPE* PFN_CreateDevice)(IDirect3D9*, UINT, D3DDEVTYPE, HWND, DWORD, D3DPRESENT_PARAMETERS*, IDirect3DDevice9**);
static PFN_Present o_Present = nullptr;
static PFN_Reset o_Reset = nullptr;
static PFN_SCPresent o_SCPresent = nullptr;
static PFN_CreateDevice o_CreateDevice = nullptr;
static PFN_CreateTexture o_CreateTexture = nullptr;

static HRESULT STDMETHODCALLTYPE hk_CreateTexture(IDirect3DDevice9* dev, UINT w, UINT h, UINT levels, DWORD usage, D3DFORMAT fmt, D3DPOOL pool, IDirect3DTexture9** out, HANDLE* sh)
{
	// D3D9Ex has no managed pool: lockable default-pool textures instead
	if (g_isEx && pool == D3DPOOL_MANAGED) { pool = D3DPOOL_DEFAULT; usage |= D3DUSAGE_DYNAMIC; }
	bool eyeRT = (usage & D3DUSAGE_RENDERTARGET) && w == h && (int)w == g_eyeW && (fmt == D3DFMT_A8R8G8B8 || fmt == D3DFMT_X8R8G8B8);
	HANDLE share = nullptr;
	HRESULT hr;
	if (eyeRT && g_isEx && !sh && levels == 1)
	{
		hr = o_CreateTexture(dev, w, h, levels, usage, fmt, pool, out, &share);
		if (FAILED(hr)) { share = nullptr; hr = o_CreateTexture(dev, w, h, levels, usage, fmt, pool, out, sh); }
	}
	else
		hr = o_CreateTexture(dev, w, h, levels, usage, fmt, pool, out, sh);
	if (SUCCEEDED(hr) && out && *out && eyeRT)
	{
		AddCandidate(*out, share);
		Log("render target %ux%u fmt %d levels %u -> candidate %p shared %p", w, h, fmt, levels, *out, share);
	}
	else if (FAILED(hr))
		Log("CreateTexture %ux%u fmt %d usage %08x pool %d FAILED %08x", w, h, fmt, usage, pool, hr);
	return hr;
}

typedef HRESULT(STDMETHODCALLTYPE* PFN_CreateVB)(IDirect3DDevice9*, UINT, DWORD, DWORD, D3DPOOL, IDirect3DVertexBuffer9**, HANDLE*);
typedef HRESULT(STDMETHODCALLTYPE* PFN_CreateIB)(IDirect3DDevice9*, UINT, DWORD, D3DFORMAT, D3DPOOL, IDirect3DIndexBuffer9**, HANDLE*);
typedef HRESULT(STDMETHODCALLTYPE* PFN_CreateCube)(IDirect3DDevice9*, UINT, UINT, DWORD, D3DFORMAT, D3DPOOL, IDirect3DCubeTexture9**, HANDLE*);
typedef HRESULT(STDMETHODCALLTYPE* PFN_CreateVol)(IDirect3DDevice9*, UINT, UINT, UINT, UINT, DWORD, D3DFORMAT, D3DPOOL, IDirect3DVolumeTexture9**, HANDLE*);
static PFN_CreateVB o_CreateVB = nullptr;
static PFN_CreateIB o_CreateIB = nullptr;
static PFN_CreateCube o_CreateCube = nullptr;
static PFN_CreateVol o_CreateVol = nullptr;
static HRESULT STDMETHODCALLTYPE hk_CreateVB(IDirect3DDevice9* d, UINT len, DWORD usage, DWORD fvf, D3DPOOL pool, IDirect3DVertexBuffer9** out, HANDLE* sh)
{
	if (g_isEx && pool == D3DPOOL_MANAGED) { pool = D3DPOOL_DEFAULT; usage |= D3DUSAGE_DYNAMIC; }
	HRESULT hr = o_CreateVB(d, len, usage, fvf, pool, out, sh);
	if (FAILED(hr)) Log("CreateVertexBuffer %u usage %08x pool %d FAILED %08x", len, usage, pool, hr);
	return hr;
}
static HRESULT STDMETHODCALLTYPE hk_CreateIB(IDirect3DDevice9* d, UINT len, DWORD usage, D3DFORMAT fmt, D3DPOOL pool, IDirect3DIndexBuffer9** out, HANDLE* sh)
{
	if (g_isEx && pool == D3DPOOL_MANAGED) { pool = D3DPOOL_DEFAULT; usage |= D3DUSAGE_DYNAMIC; }
	HRESULT hr = o_CreateIB(d, len, usage, fmt, pool, out, sh);
	if (FAILED(hr)) Log("CreateIndexBuffer %u usage %08x pool %d FAILED %08x", len, usage, pool, hr);
	return hr;
}
static HRESULT STDMETHODCALLTYPE hk_CreateCube(IDirect3DDevice9* d, UINT e, UINT lv, DWORD usage, D3DFORMAT fmt, D3DPOOL pool, IDirect3DCubeTexture9** out, HANDLE* sh)
{
	if (g_isEx && pool == D3DPOOL_MANAGED) { pool = D3DPOOL_DEFAULT; usage |= D3DUSAGE_DYNAMIC; }
	HRESULT hr = o_CreateCube(d, e, lv, usage, fmt, pool, out, sh);
	if (FAILED(hr)) Log("CreateCubeTexture %u fmt %d FAILED %08x", e, fmt, hr);
	return hr;
}
static HRESULT STDMETHODCALLTYPE hk_CreateVol(IDirect3DDevice9* d, UINT w, UINT h, UINT dp, UINT lv, DWORD usage, D3DFORMAT fmt, D3DPOOL pool, IDirect3DVolumeTexture9** out, HANDLE* sh)
{
	if (g_isEx && pool == D3DPOOL_MANAGED) { pool = D3DPOOL_DEFAULT; usage |= D3DUSAGE_DYNAMIC; }
	HRESULT hr = o_CreateVol(d, w, h, dp, lv, usage, fmt, pool, out, sh);
	if (FAILED(hr)) Log("CreateVolumeTexture FAILED %08x", hr);
	return hr;
}
static bool g_inPresent = false;

static void* Patch(void* obj, int index, void* fn)
{
	void** vt = *(void***)obj;
	void* old = vt[index];
	if (old == fn) return nullptr;
	DWORD prot;
	VirtualProtect(&vt[index], sizeof(void*), PAGE_EXECUTE_READWRITE, &prot);
	vt[index] = fn;
	VirtualProtect(&vt[index], sizeof(void*), prot, &prot);
	return old;
}

static void OnFrame(IDirect3DDevice9* dev, bool before)
{
	InitVR();
	if (before)
	{
		// Submit only after a WaitGetPoses, or the compositor answers 101 (DoNotHaveFocus)
		ScoreCapture(dev);
		if ((g_hmd && g_waited) || g_mock) SubmitFrame(dev);
		if (g_hmd && g_frames == 300) Log("frame 300 reached; compositor running");
		return;
	}
	IDirect3DSurface9* bb = nullptr;
	UINT w = 0, h = 0;
	if (SUCCEEDED(dev->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &bb)) && bb)
	{
		D3DSURFACE_DESC d;
		bb->GetDesc(&d);
		w = d.Width; h = d.Height;
		bb->Release();
	}
	AfterPresent(w, h);
}

static HRESULT STDMETHODCALLTYPE hk_Present(IDirect3DDevice9* dev, const RECT* a, const RECT* b, HWND c, const RGNDATA* d)
{
	if (g_inPresent) return o_Present(dev, a, b, c, d);
	g_inPresent = true;
	OnFrame(dev, true);
	HRESULT hr = o_Present(dev, a, b, c, d);
	OnFrame(dev, false);
	g_inPresent = false;
	return hr;
}

static HRESULT STDMETHODCALLTYPE hk_SCPresent(IDirect3DSwapChain9* sc, const RECT* a, const RECT* b, HWND c, const RGNDATA* d, DWORD f)
{
	if (g_inPresent) return o_SCPresent(sc, a, b, c, d, f);
	IDirect3DDevice9* dev = nullptr;
	sc->GetDevice(&dev);
	g_inPresent = true;
	if (dev) OnFrame(dev, true);
	HRESULT hr = o_SCPresent(sc, a, b, c, d, f);
	if (dev) { OnFrame(dev, false); dev->Release(); }
	g_inPresent = false;
	return hr;
}

static HRESULT STDMETHODCALLTYPE hk_Reset(IDirect3DDevice9* dev, D3DPRESENT_PARAMETERS* pp)
{
	ReleaseCandidates();   // D3DPOOL_DEFAULT references must go before Reset
	ReleaseOwnEyes();
	if (g_panelTex) { g_panelTex->Release(); g_panelTex = nullptr; g_panelW = g_panelH = 0; }
	ScoreRelease();
	HRESULT hr = o_Reset(dev, pp);
	Log("Reset %ux%u windowed=%d -> %08x", pp ? pp->BackBufferWidth : 0, pp ? pp->BackBufferHeight : 0, pp ? pp->Windowed : -1, hr);
	return hr;
}

static void HookDevice(IDirect3DDevice9* dev)
{
	PollGame();   // bind the game -> proxy port now: a game UdpLink that can't get its own port may take the next one
	void* p;
	if ((p = Patch(dev, 17, (void*)hk_Present))) o_Present = (PFN_Present)p;
	if ((p = Patch(dev, 16, (void*)hk_Reset))) o_Reset = (PFN_Reset)p;
	if ((p = Patch(dev, 23, (void*)hk_CreateTexture))) o_CreateTexture = (PFN_CreateTexture)p;
	if ((p = Patch(dev, 24, (void*)hk_CreateVol))) o_CreateVol = (PFN_CreateVol)p;
	if ((p = Patch(dev, 25, (void*)hk_CreateCube))) o_CreateCube = (PFN_CreateCube)p;
	if ((p = Patch(dev, 26, (void*)hk_CreateVB))) o_CreateVB = (PFN_CreateVB)p;
	if ((p = Patch(dev, 27, (void*)hk_CreateIB))) o_CreateIB = (PFN_CreateIB)p;
	IDirect3DSwapChain9* sc = nullptr;
	if (SUCCEEDED(dev->GetSwapChain(0, &sc)) && sc)
	{
		if ((p = Patch(sc, 3, (void*)hk_SCPresent))) o_SCPresent = (PFN_SCPresent)p;
		sc->Release();
	}
	Log("device hooked %p", dev);
}

static HRESULT STDMETHODCALLTYPE hk_CreateDevice(IDirect3D9* d3d, UINT ad, D3DDEVTYPE t, HWND w, DWORD f, D3DPRESENT_PARAMETERS* pp, IDirect3DDevice9** out)
{
	HRESULT hr = E_FAIL;
	g_hwnd = (pp && pp->hDeviceWindow) ? pp->hDeviceWindow : w;
	if (g_wantEx)
	{
		IDirect3D9Ex* ex = nullptr;
		if (SUCCEEDED(d3d->QueryInterface(__uuidof(IDirect3D9Ex), (void**)&ex)) && ex)
		{
			D3DDISPLAYMODEEX mode = {};
			mode.Size = sizeof mode;
			if (pp && !pp->Windowed)
			{
				mode.Width = pp->BackBufferWidth; mode.Height = pp->BackBufferHeight;
				mode.RefreshRate = pp->FullScreen_RefreshRateInHz; mode.Format = pp->BackBufferFormat;
				mode.ScanLineOrdering = D3DSCANLINEORDERING_PROGRESSIVE;
			}
			IDirect3DDevice9Ex* dex = nullptr;
			g_isEx = true;   // the hooks below must convert managed resources from the very first one
			hr = ex->CreateDeviceEx(ad, t, w, f, pp, (pp && !pp->Windowed) ? &mode : nullptr, &dex);
			ex->Release();
			if (SUCCEEDED(hr)) *out = dex;
			else g_isEx = false;
			Log("CreateDeviceEx %ux%u windowed=%d -> %08x", pp ? pp->BackBufferWidth : 0, pp ? pp->BackBufferHeight : 0, pp ? pp->Windowed : -1, hr);
		}
	}
	if (!g_isEx)
	{
		hr = o_CreateDevice(d3d, ad, t, w, f, pp, out);
		Log("CreateDevice %ux%u windowed=%d -> %08x", pp ? pp->BackBufferWidth : 0, pp ? pp->BackBufferHeight : 0, pp ? pp->Windowed : -1, hr);
	}
	if (SUCCEEDED(hr) && out && *out) HookDevice(*out);
	return hr;
}

// ---------------------------------------------------------------------------
// exports
// ---------------------------------------------------------------------------
extern "C" IDirect3D9* WINAPI Proxy_Direct3DCreate9(UINT sdk)
{
	ReadConfig();
	IDirect3D9* d3d = nullptr;
	if (g_wantEx)
	{
		PFN_Create9Ex fx = (PFN_Create9Ex)Real("Direct3DCreate9Ex");
		IDirect3D9Ex* ex = nullptr;
		if (fx && SUCCEEDED(fx(sdk, &ex)) && ex) d3d = ex;
	}
	if (!d3d)
	{
		PFN_Create9 fn = (PFN_Create9)Real("Direct3DCreate9");
		d3d = fn ? fn(sdk) : nullptr;
	}
	if (d3d)
	{
		void* p = Patch(d3d, 16, (void*)hk_CreateDevice);
		if (p) o_CreateDevice = (PFN_CreateDevice)p;
	}
	Log("Direct3DCreate9(%u) -> %p (Ex wanted %d)", sdk, d3d, g_wantEx);
	return d3d;
}

extern "C" HRESULT WINAPI Proxy_Direct3DCreate9Ex(UINT sdk, IDirect3D9Ex** out)
{
	PFN_Create9Ex fn = (PFN_Create9Ex)Real("Direct3DCreate9Ex");
	HRESULT hr = fn ? fn(sdk, out) : E_FAIL;
	if (SUCCEEDED(hr) && out && *out)
	{
		void* p = Patch(*out, 16, (void*)hk_CreateDevice);
		if (p) o_CreateDevice = (PFN_CreateDevice)p;
	}
	Log("Direct3DCreate9Ex(%u) -> %08x", sdk, hr);
	return hr;
}

#define FWD(name, ret, args, call, fail) \
	extern "C" ret WINAPI Proxy_##name args { typedef ret (WINAPI* F) args; F f = (F)Real(#name); return f ? f call : fail; }
FWD(D3DPERF_BeginEvent, int, (D3DCOLOR c, LPCWSTR n), (c, n), 0)
FWD(D3DPERF_EndEvent, int, (), (), 0)
FWD(D3DPERF_GetStatus, DWORD, (), (), 0)
FWD(D3DPERF_QueryRepeatFrame, BOOL, (), (), FALSE)
FWD(D3DPERF_SetMarker, void, (D3DCOLOR c, LPCWSTR n), (c, n), (void)0)
FWD(D3DPERF_SetOptions, void, (DWORD o), (o), (void)0)
FWD(D3DPERF_SetRegion, void, (D3DCOLOR c, LPCWSTR n), (c, n), (void)0)

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID)
{
	if (reason == DLL_PROCESS_ATTACH)
	{
		DisableThreadLibraryCalls(inst);
		char p[MAX_PATH];
		GetModuleFileNameA(inst, p, MAX_PATH);
		g_dir = p;
		g_dir = g_dir.substr(0, g_dir.find_last_of("\\/") + 1);
	}
	else if (reason == DLL_PROCESS_DETACH)
	{
		if (g_hmd) vr::VR_Shutdown();
		if (g_log) fclose(g_log);
	}
	return TRUE;
}
