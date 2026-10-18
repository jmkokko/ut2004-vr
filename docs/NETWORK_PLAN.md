# Network play in VR: plan

Status: **parked**. Local gameplay comes first; this starts once the user is happy with it. A working document:
tick boxes, add findings and decisions as we go.

Today, joining a server (including our own dedicated server) runs without VR: the server decides the player
class, so the client gets the stock one, and the proxy shows the game on a big screen in the headset (played flat).
Full VR needs the server to take part.

## How UT2004 networking constrains this
- **Server-authoritative.** The owning client predicts its own movement and sends compressed moves (`ServerMove`) to
  the server, which simulates them and corrects the client (`ClientAdjustPosition`) when they disagree.
- **Weapons fire on the server**, which traces from the shooter's eye (`EyePosition`) along the shooter's aim
  (`AdjustAim`). The server must know where our gun is and where it points.
- To verify before coding (phase 1, step 1): `PlayerController.ReplicateMove` / `ServerMove` in 3374 (what's sent,
  how rotation is compressed), the server-side fire path (`ServerStartFire`, `GetFireStart`, `AdjustAim`), and what
  `PlayerTick` / `PostBeginPlay` run where on a listen server.

## What breaks today (from the code)
| Area | Today | In a network game |
|---|---|---|
| Head-following (room-scale walking) | `Pawn.Move(...)` directly in `VRFollowHead` | not replicated: the server corrects it away |
| Teleport | `Pawn.SetLocation(Dest)` in `VRTeleportGo` | client-only jump, rubber-banded back |
| VR movement | `ProcessMove(...)` called directly in `VRPlayerMove` | skips `ReplicateMove`, nothing reaches the server |
| Shot origin | `VRPawn.EyePosition` = the muzzle computed on the client | the server has no muzzle: shots start at the wrong place |
| Aim | `AdjustAim` returns `Rotation` when `GunActive()` (needs hand data) | false on the server: falls back to stock aim |
| Tracking link | spawned for every non-dedicated controller | a listen server would start links for other players' controllers |

## Phases

### 1. Network-safe, no VR changes yet
- [ ] Read the netcode listed above; write the findings here.
- [ ] Client-only logic (tracking link, eye textures, mirror interaction, menus, gun model, laser, HUD) only for
      the locally controlled player (`Player != None` / `IsLocalPlayerController()`), never for remote players'
      controllers on a server.
- [ ] Non-VR players with `VRPlayerController` play exactly like stock (no tracking data -> stock paths).
- [ ] Test: listen server + one ordinary client; dedicated server + one ordinary client.

### 2. Movement through UT's networking
- [ ] VR movement goes through `ReplicateMove`: stick movement, gaze steering, jump, dodge, crouch (they already use
      UT's flags: `bPressedJump`, `DoubleClickMove`, `bDuck`).
- [ ] Head-following becomes acceleration / move requests inside those moves, not direct pawn moves.
- [ ] Teleport becomes a server request (`ServerVRTeleport(Dest)`), validated: distance (`TeleportMaxDist`), line of
      sight, collision at the destination.
- [ ] Snap and smooth turns in the view rotation (already sent).
- [ ] Test: a client walking, turning, teleporting, jumping, dodging with no corrections on a quiet localhost.

### 3. Aiming and firing
- [ ] The client sends gun position (relative to the pawn) and aim to the server: ~30 Hz plus with every shot,
      unreliable (~20 bytes). Full-precision rotation: UT's compressed view rotation would make the hand aim jitter.
- [ ] Server side: `VRPawn.EyePosition` and `AdjustAim` use those values (shots, beams, projectiles, hitscan).
- [ ] The laser stays client-only.
- [ ] Test: hitscan (Shock, Lightning), projectiles (Rocket, Flak), beams (Link) hit where the laser points, from
      the client, on both server types.

### 4. Comfort under corrections
- [ ] Server corrections snap the pawn: smooth the eye position toward the corrected one over a few frames, ignore
      small ones. A visible jump in the headset is motion sickness.
- [ ] Test with real latency (an artificial delay on localhost, e.g. 50-150 ms) and some packet loss.

### 5. How other players see a VR player (optional)
- [ ] Replicate head direction and gun pose so the third-person model looks and aims where the VR player does.

### 6. Packaging and servers
- [ ] Server: `VRMutator` in the mutator list / URL, `UT2004VR` in `ServerPackages` (clients need the same version).
- [ ] Only on servers we run; tell other players / admins that a modded controller class is in use.

### 7. Test setup
- [ ] Configurable proxy ports per process (today two proxies on one PC would both take UDP 7791).
- [ ] One PC: `ucc server` + two clients, mock mode for scripted checks; then the real headset.
- [ ] Scripted test sequences (`TestExec` / `MenuTestExec`) that join a server and log state.

## Order and size
Phases 1-3 make it playable, 4 makes it comfortable, 5-6 are polish and setup. Riskiest: phase 2 (room-scale
movement and teleport consistent with the server) and phase 4 (corrections in the headset). Expect several
sessions. Start with phase 1 plus the two-instance harness (phase 7) so each step can be verified like the local
features were.

## Open questions
- Does the 3374 netcode allow extra per-move data cleanly (a `ServerMove` override), or is a separate unreliable
  RPC better for the head-following offset?
- How do Onslaught vehicles behave for a VR client (driver camera is client-side; turrets aim from the server)?
- Assault is out anyway until OldUnreal fixes the round-start crash (see MODLOG).

## Decisions
- 2026-10-14: network VR is deferred until local gameplay is finished (user's call). Meanwhile servers show the game
  on a big screen in the headset (`ScreenDistance`, `ScreenWidth` in `UT2004VR_proxy.ini`).
