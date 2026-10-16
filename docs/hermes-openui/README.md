# Inline OpenUI in Hermez

Build 180 added native Dart rendering for the 70-component OpenUI v1 catalog shared with Hermes Desktop. Build 182 adds three Conduit-only image components (73 in total); see Images below. The reference schema and five example programs live in `references/`. The React SDK cannot render Flutter widgets directly, so this port implements the bounded language contract with Flutter controls and the existing Hermez visual theme. It does not use a WebView, OpenUI Gateway or a separate conversation.

These entries are this application's custom library. They do not include every component or visual treatment in the [OpenUI demos](https://www.openui.com/demos). Those apps combine their own components with photo, map and live-data sources. There is no map component; an `Avatar` displays initials. Catalog coverage does not establish demo parity or individual phone testing of every component.

The native surface supplies a transparent Material host. Bare tabs, selectors and lists must work in the custom chat even when the generated program does not wrap them in a Card. The gallery checks deliberately run without a Scaffold to catch that missing-host failure.

Completed assistant responses can contain separate `openui` and `a2ui` fences, with Markdown around them. A2UI keeps its strict v0.9 JSONL contract. OpenUI accepts one inline `root = Stack([...])` statement, positional arguments, literal data, at most 64 KiB, 200 components and 16 component levels. Unsupported or partial programs fall back to source text. Generated content cannot execute code, call tools, open files or fetch anything except image `src` values (see Images).

Explicit buttons use the existing `[A2UI_INTERACTION]` envelope with `context.renderer=openui`, the requested message and current form values, including unchanged defaults. Local controls do not send messages or change operational state. Drafts remain unsent. Busy, read-only, changed-connection and wrong-chat interactions cannot submit; both renderers reuse the existing chat ownership guard.

Each Conduit turn advertises its current capability. Responses mode uses the existing instructions field. Older Desktop JSON-RPC gateways have no such field, so Conduit appends a fixed client capability note to normal turn input. Server history retains that note; the phone hides only that exact note when presenting the user row. Action JSON remains unchanged. The marker is idempotent across retries and applies only to the current client turn. This avoids modifying or restarting the messaging gateway.

Schema authority: until Desktop migrates to the full `@openuidev/react-ui` `openuiLibrary`, `references/catalog.schema.json` here is the reference copy and `lib/features/hermes/services/hermes_openui_schema.dart` is generated from it (`python tool/generate_hermes_openui_schema.py`). Never edit the Dart schema constants by hand. The first 70 entries were copied from `hermes-openui-desktop/dist`; `Image`, `ImageBlock` and `ImageGallery` were added here only and are not in the installed Desktop plugin. The parity test therefore compares the Dart catalog with this reference copy and checks fixture coverage of all 73 components. After the Desktop migration, restore a comparison against Desktop's generated schema (or the openuiLibrary export) for the shared components.

## Images

`Image(alt, src?)`, `ImageBlock(src, alt?)` and `ImageGallery([{src, alt, details}, ...])` (1 to 12 items, string fields only) follow the argument order of the published `@openuidev/react-ui` genui-lib. `ImageText` and `ImageTextLarge` are not implemented yet. `src` may be:

- an `https://` or `http://` image URL on any host, including private LAN or Tailscale hosts (userinfo credentials are rejected; URLs are limited to 2048 characters). Android cleartext is already permitted by the app manifest, and Dart sockets are not subject to the platform cleartext policy;
- a `data:image/(png|jpeg|gif|webp|avif|bmp);base64,` URI. The whole program is capped at 64 KiB, so the practical limit is about 48 KB; SVG data is rejected;
- a path declared with `MEDIA:` in the same assistant message, shown through the existing authenticated artifact preview. Undeclared paths show the placeholder.

`javascript:`, `file:`, `content:`, `intent:` and other schemes are rejected. Only the image is requested, by a plain GET without cookies, credentials or custom headers, limited to 8 MB and `image/*` responses. Rejected, missing, undecodable or failed images show a themed placeholder with the alt text, never an error tile. Tapping a loaded image opens a local full-screen pinch-zoom viewer (double tap zooms); it sends nothing. `ImageGallery` is a swipeable page view with dots. Rendering fetches a third-party URL, so the remote server learns the phone's address and the time of the request.

## Older replies

Once a newer user turn exists, an older assistant reply can no longer send: OpenUI `Button`s are disabled while tabs, selections and galleries keep working, and an A2UI surface takes the read-only lock (local disclosures still open). The model should put actions in the latest reply.

Developer checks:

```powershell
..\toolchain\flutter\bin\flutter.bat test test/features/hermes/hermes_openui_test.dart test/features/hermes/hermes_rich_output_parser_test.dart test/features/hermes/hermes_a2ui_surface_test.dart
..\toolchain\flutter\bin\cache\dart-sdk\bin\dart.exe tool/check_hermes_openui.dart docs/hermes-openui/references/example-overview.openui
```

To try it, ask Hermes: “Using OpenUI, show a synthetic weekend comparison with a cost chart and an activity form. Keep it an example; do not book or schedule anything.” Change a field, then press its explicit chat button. The next reply should use the selected value and unchanged defaults in that same conversation. Ask for an A2UI citation or draft separately to exercise both renderers.

Unsaved presentation edits can reset when the surface unmounts; accepted form values remain in chat history. No claims are made for arbitrary component combinations, model accuracy or changes made by tools after a conversational request.
