# Hermes push (UnifiedPush) in Hermez

Build 184 is installed and paired on the S25 Ultra. All eight categories use
Conduit with ntfy fallback. [Completion receipt](CODEX-2026-10-19.md).

Native notifications from the Umbrel. The phone's ntfy app is only the
*distributor*; Hermez registers with it through the UnifiedPush connector,
decrypts pushes itself and renders them as Hermez notifications. Design:
`CONDUIT-NOTIFICATIONS-SPEC-20261019.md` (on the Umbrel in `~/.jarvis/docs/`).

## Pieces

| Where | What |
| --- | --- |
| `android/.../push/PushReceiver.kt` | UnifiedPush entry (connector 3.3.5, `MessagingReceiver`). Runs with no Flutter engine. |
| `PushIntake.kt`, `PushPolicy.kt`, `PushEnvelope.kt` | Parse, TTL, dedup (last 500 ids), category switches. Pure Kotlin, JVM-tested. |
| `PushRenderer.kt`, `PushChannels.kt` | Channels `hermez_<category>_v1`, group summaries, Approve/Deny actions. Critical never bypasses Do Not Disturb (no `setBypassDnd`, normal notification sound usage). |
| `ApprovalActionReceiver.kt`, `PushWorkers.kt` | Shade actions run in WorkManager: re-read the request, compare digest, send one idempotent decision. Approve needs an unlocked phone (`setAuthenticationRequired`). |
| `PushVault.kt` | Device token and gateway origin, AES-GCM with an Android Keystore key. |
| `pigeons/conduit_push_api.dart` | Dart bridge. Regenerate with `dart tool/pigeon_codegen/bin/generate.dart`. |
| `lib/features/push/` | Models, gateway client, health evaluation, Approvals screens, pairing, settings section. |

## Pairing

1. On the Umbrel: `docker exec hermes-notify notifyctl pair` prints a one-time code (valid five minutes).
2. In Hermez: Settings, Notifications, Push from Hermes, "Pair this phone". Enter the gateway address
   (default `https://<hermes host>:8450`) and the code.
3. Install ntfy from the Play Store and open it once if "ntfy is not installed" shows.
4. Set Hermez **and** ntfy to Unrestricted battery use and remove them from Samsung "sleeping apps".

## Deep links

`hermez://hermes/profile/hermes/approvals[/<id>]`, `.../live/<session>`, `.../conversations?thread=<n>`,
`.../home?brief=<date>`.

## adb recipes

Debug and profile builds include `DebugPushReceiver` (permission `android.permission.DUMP`, so only adb can use it):

```
adb shell am broadcast -n app.cogwheel.conduit.debug/app.cogwheel.conduit.push.DebugPushReceiver \
  --es envelope '{"v":1,"t":"notify","id":"dbg1","ts":<epoch>,"cat":"alerts","title":"Test","body":"Hello"}'
adb shell dumpsys notification --noredact | grep -A12 app.cogwheel.conduit
adb shell am kill app.cogwheel.conduit.debug    # test with the process dead
```

## Recovery and renewal

On start and resume, Hermez checks the gateway epoch, renews device tokens with
less than 30 days remaining, and queues inbox catch-up. Inbox pages are validated
before the cursor is committed and replay through the same native intake and
dedup path as live pushes. A changed epoch or revoked token requires pairing
again. Temporary network errors retain the pairing. Native WorkManager retries
inbox requests and acknowledges duplicate deliveries as well as new ones.

## Not in this build

QR scanning of the pairing code. Manual code pairing is supported; changing the
Android application id requires pairing the new installation.
