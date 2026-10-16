# Inline OpenUI in Hermez

Build 180 adds native Dart rendering for the same 70-component OpenUI v1 catalog as Hermes Desktop. Both use the same schema and four example programs in `references/`. The React SDK cannot render Flutter widgets directly, so this port implements the bounded language contract with Flutter controls and the existing Hermez visual theme. It does not use a WebView, OpenUI Gateway or a separate conversation.

Completed assistant responses can contain separate `openui` and `a2ui` fences, with Markdown around them. A2UI keeps its strict v0.9 JSONL contract. OpenUI accepts one inline `root = Stack([...])` statement, positional arguments, literal data, at most 64 KiB, 200 components and 16 component levels. Unsupported or partial programs fall back to source text. Generated content cannot execute code, call tools, fetch URLs or open files.

Explicit buttons use the existing `[A2UI_INTERACTION]` envelope with `context.renderer=openui`, the requested message and current form values, including unchanged defaults. Local controls do not send messages or change operational state. Drafts remain unsent. Busy, read-only, changed-connection and wrong-chat interactions cannot submit; both renderers reuse the existing chat ownership guard.

Each Conduit turn advertises its current capability. Responses mode uses the existing instructions field. Older Desktop JSON-RPC gateways have no such field, so Conduit appends a fixed client capability note to normal turn input. Server history retains that note; the phone hides only that exact note when presenting the user row. Action JSON remains unchanged. The marker is idempotent across retries and applies only to the current client turn. This avoids modifying or restarting the messaging gateway.

Schema authority: `hermes-openui-desktop/dist/catalog.schema.json` in the October 7 Codex workspace. Copy a reviewed Desktop catalog and examples here together; run `python tool/generate_hermes_openui_schema.py`, then the focused checks. Never edit Dart schema constants by hand. The parity check compares the decoded schema and verifies fixture coverage of all 70 components.

Developer checks:

```powershell
..\toolchain\flutter\bin\flutter.bat test test/features/hermes/hermes_openui_test.dart test/features/hermes/hermes_rich_output_parser_test.dart test/features/hermes/hermes_a2ui_surface_test.dart
..\toolchain\flutter\bin\cache\dart-sdk\bin\dart.exe tool/check_hermes_openui.dart docs/hermes-openui/references/example-overview.openui
```

To try it, ask Hermes: “Using OpenUI, show a synthetic weekend comparison with a cost chart and an activity form. Keep it an example; do not book or schedule anything.” Change a field, then press its explicit chat button. The next reply should use the selected value and unchanged defaults in that same conversation. Ask for an A2UI citation or draft separately to exercise both renderers.

Unsaved presentation edits can reset when the surface unmounts; accepted form values remain in chat history. No claims are made for arbitrary component combinations, model accuracy or changes made by tools after a conversational request.
