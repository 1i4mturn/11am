# cole: video, film and audio

> **The one-liner:** Cole turns talking into publishable video. Record, edit by editing the transcript, clean the audio, caption it and cut the clips, without learning a timeline.
> **Package:** Add-on · **Monogram:** `co` · **App name:** *Cole*

## Role in the team
Cole owns moving image and sound: recording (screen, camera, audio), transcript-first editing, captions, clean-up, short-form clips, and the creative side (concepts, scripts, storyboards, motion templates). His capture-and-transcribe engine is shared with Leo's meeting notes.

## Replaces / enhances
Loom (screen + camera recording), Descript (transcript editing, filler removal), CapCut (captions, reels), Premiere/Final Cut for simple edits, Voice Memos and simple podcast editing, Rev/Otter (transcripts), subtitle tools.

## Use cases
1. **Loom-style update:** record screen + camera bubble → auto-trim the start and end → remove silences → captions → export or share via iCloud link. Two minutes from stop to send.
2. **Edit by transcript:** delete a sentence in the transcript and it's cut from the video. Remove all "um/uh/like" with one click. Reorder paragraphs to reorder clips.
3. **Long → short:** a 30-minute podcast or webinar becomes 3–5 vertical clips with captions and a hook. Cole picks highlights (with reasons), reframes to faces (Vision), and adds your brand's caption style.
4. **Clean audio:** noise removal (DeepFilterNet), loudness normalisation, de-esser-lite, voice/music separation for B-roll videos.
5. **Script → teleprompter → record:** William writes the script in your voice, Cole shows a teleprompter overlay while recording, then aligns the takes to the script.
6. **Concepts and storyboards** (ported): content ideas, scripts, shot lists, storyboards for a campaign with Conner.
7. **Subtitles and translation:** SRT/VTT export; translated captions (Apple Translation).
8. **Voiceover:** narrate slides with your own voice (Apple Personal Voice, with consent) or a neutral TTS voice.

## Features

### v1 (MVP)
- **Recorder:** screen (full/window/area via ScreenCaptureKit), camera (bubble or side-by-side), mic + system audio, presenter overlay, pause/resume, countdown, **notch recording indicator with timer and stop**.
- **Transcription:** WhisperKit, local, word-level timestamps; speaker labels (SpeakerKit).
- **Transcript editor:** text-based cutting (delete words → cut), strike-through preview, restore; filler-word and silence removal with a sensitivity control; chapters.
- **Simple timeline** under the transcript: clips, trim handles, B-roll/image overlays, music bed with ducking, titles.
- **Captions:** styles (monochrome defaults + brand from Robert), burn-in or sidecar (SRT/VTT).
- **Audio clean-up:** noise suppression, loudness normalisation (EBU R128 target presets).
- **Export:** H.264/HEVC/ProRes via AVFoundation/VideoToolbox (hardware), presets (YouTube, LinkedIn, Instagram/TikTok 9:16, podcast audio), GIF.

### v2
- **Auto-clips** for socials (highlight selection + 9:16 reframing with face tracking + captions + hook title).
- **Teleprompter** + script alignment (William scripts).
- **Storyboards, concepts, scripts** (ported) with Robert visuals.
- **Motion templates:** titles, lower thirds, end cards (Robert brand).
- **Stock B-roll search** (Pexels API) and suggestions from the transcript.
- **Voiceover** (Personal Voice / TTS).
- **Translation** of captions.

### Later
- Multicam (two cameras / iPhone as a second angle via Continuity Camera).
- Basic colour correction and LUTs.
- AI dubbing in your voice (only your own voice, with consent).

### Not building
- A pro NLE (Final Cut/Resolve level: colour grading suites, VFX, compositing).
- Video hosting or streaming (export files; share via iCloud/Drive links).
- Live streaming.
- Voice cloning of anyone other than the user.

## How the AI is involved

| Feature | Task class | Autonomy | Trigger |
|---|---|---|---|
| Transcription + diarisation | `transcribe` (WhisperKit, SpeakerKit), always local | L3 | Recording ends / import |
| Filler and silence detection | Deterministic (word timestamps + audio energy, à la auto-editor) | L0 (preview) → apply | Button |
| Highlight selection | `summarise.medium` over the transcript → ranked segments with reasons | L0 (variants) | Ask |
| Reframing | Vision face/body tracking (no LLM) | L3 | Clip generation |
| Noise suppression | DeepFilterNet (no LLM) | L0 → apply | Button |
| Chapters and titles | `summarise.medium` | Suggestion | Transcript ready |
| Scripts / concepts | `draft.medium` + William voice | Draft | Ask |
| B-roll suggestions | `extract.small` (visual nouns) + search API | Suggestion | Ask |
| Voiceover | `AVSpeechSynthesizer` / Personal Voice / Kokoro | Draft | Ask |

## Works with
- **William:** scripts, captions copy, articles from transcripts ("turn this video into a blog post").
- **Robert:** brand, caption styles, motion templates, thumbnails.
- **Conner:** campaign briefs and marketing goals.
- **Leo:** shares the capture/transcribe engine for meetings; schedules recording sessions.
- **James:** references.
- **Bolton:** media library, transcripts searchable.
- **Harris:** video lessons (your recordings as learning material).

## Design and visual identity
- **Pattern:** film perforations / frame lines.
- **Motion:** playhead scrubs; transcript words highlight as they play.
- **Recording is the one place colour appears in the chrome:** the red recording dot (universal meaning, safety).
- **Tone:** practical, creative. "Cut 2:14 of silence and 37 filler words. The video is now 6:02."

### Wireframe: transcript-first editor
```
┌──────────────────────────────────────────────────────────────────────────────────┐
│ co  Product update · Oct                         preset: LinkedIn ▾   export ▾   │
├──────────────┬───────────────────────────────────────────────────┬───────────────┤
│ Media        │  ┌──────────────────────────────────────────┐     │ cole          │
│  rec_1028    │  │                                          │     │               │
│  logo.png    │  │        [ preview · 16:9 ]                │     │ Cut fillers   │
│  music.m4a   │  │                                          │     │ 37 found ▸    │
│ ─ projects ─ │  └──────────────────────────────────────────┘     │ Cut silences  │
│  Oct update  │   ▶ 02:14 / 06:02                                 │ 2:14 total ▸  │
│  Webinar     │ ─ transcript ───────────────────────────────────  │               │
│ Clips      3 │  Liam  So this month we ~~um~~ shipped the new    │ Clips         │
│ Templates    │        notch, and ~~like~~ the big one is that    │ 3 suggested ▸ │
│ + Tune…      │        Marc now drafts replies in your voice.     │               │
│              │  ▕▇▇▇▇▕▇▇▇▕▇▇▇▇▇▇▇▕▇▇▕▇▇▇▇▕  timeline              │ Clean audio ▸ │
├──────────────┴───────────────────────────────────────────────────┴───────────────┤
│ ⌘K · ⌘J ask cole · transcript: whisperkit (local) · ● on-device                  │
└──────────────────────────────────────────────────────────────────────────────────┘
```

### Wireframe: notch while recording
```
        ┌──────────┐
  ● rec │  notch   │ 04:12  ■        hover → [pause] [stop] [discard] · mic ▂▅▇▅▂
```

## Usability
- **Shortcuts:** ⌘⇧5-style global "record" hotkey (configurable, e.g. ⌃⌥R) · space play/pause · J/K/L shuttle · ⌫ on transcript selection = cut · ⌘Z restores · ⌘E export.
- **Onboarding:** permissions explained (Screen & System Audio Recording, Camera, Microphone) → test recording → "edit by deleting words" tutorial on the test clip.
- **Non-destructive:** the original media is never modified; edits are an edit decision list.
- **Empty state:** perforation pattern; "Record something, or drop a video."

## Notch and iPhone
- **Notch:** recording indicator with timer and stop (genuinely useful); export progress ring; "3 clips ready".
- **iPhone:** capture footage (auto-syncs into the Mac project), Continuity Camera as webcam/second angle, review exports, teleprompter for recording on the phone.

## Mac integration
ScreenCaptureKit (screen + system audio; presenter overlay where available) · AVFoundation (`AVCaptureSession` camera/mic, `AVMutableComposition`, `AVVideoComposition`, `AVAssetExportSession`/`AVAssetWriter`) · VideoToolbox (hardware encode) · Core Audio taps · Vision (face/body tracking, saliency) · Metal/Core Image (captions and titles rendering, effects) · WhisperKit/SpeakerKit · `AVSpeechSynthesizer` + Personal Voice · Translation · Continuity Camera · Photos (import) · App Intents ("Start recording", "Make clips from…").
**Permissions:** Screen & System Audio Recording, Camera, Microphone, Photos (optional), Personal Voice (optional).

## Backend
- **Mostly Swift** (AVFoundation is Apple-native and hardware-accelerated; Rust adds little here).
- **Rust `core/cole`:** project model (media refs, EDL: list of source ranges + overlays + audio ops), transcript model (words, timestamps, speakers, edits), filler/silence detector (timestamps + energy), highlight ranker interface, caption layout (line breaking, timing), DeepFilterNet integration (`deep_filter` crate, offline processing), export job queue, port of motion templates.
- **Tables:** `projects(id, title, preset, edl_json, updated_at)`, `media(id, blob_ref|path, kind, duration, fps, transcript_id)`, `transcripts(id, media_id, words_ref, speakers_json, language)`, `clips(id, project_id, ranges_json, reason, aspect, status)`, `exports(id, project_id, preset, path, status)`.
- **Port from current repo:** `apps/cole/src/lib/{video/engine.ts (scripts, concepts, storyboards), motion/templates.ts, transcribe/whisper.ts → WhisperKit, ffmpeg/convert.ts → AVFoundation}`.

## Lower-end Macs
- **Tier A:** recording and hardware export are fine (Apple media engines); transcription with a small Whisper model (slower, after recording); DeepFilterNet offline (fine); highlight selection via small model or cloud; no live captions.
- **Tier B:** larger Whisper (turbo) models; local highlights.
- **Tier C+:** everything local and fast, including near-real-time transcripts.

## Open source to study
`WyattBlue/auto-editor` · `browser-use/video-use` (+ freecut fork) · `motion-canvas/motion-canvas` · `Rikorose/DeepFilterNet` · `facebookresearch/demucs` · `m-bain/whisperX` · `argmaxinc/argmax-oss-swift` · `wulkano/Kap` · `CapSoftware/Cap` (AGPL: study) · `obsproject/obs-studio` (GPL: study) · `mifi/lossless-cut` (GPL: study) · `remotion-dev/remotion` (licence: reference).

## Tunable by Johnny
Caption styles; export presets; clip rules (length, number, hooks); filler-word list (per language); intro/outro templates; auto-actions after recording ("always remove silences and add captions").

## Risks and open questions
- **Performance on long recordings:** generate proxies; keep the EDL lightweight; transcribe in chunks.
- **Recording consent** (other people on screen or in meetings). Show a reminder when system audio includes a call app.
- **Format quirks** (variable frame rate screen recordings). Normalise on import.
- **Open question:** share links. Use iCloud Drive/Dropbox share links rather than hosting video yourself.

## Build checklist
- [ ] Recorder (screen, camera, mic, system audio) + notch indicator
- [ ] WhisperKit transcription with word timestamps + SpeakerKit
- [ ] Transcript editor ↔ EDL ↔ preview sync
- [ ] Filler and silence removal
- [ ] Simple timeline (clips, overlays, music ducking, titles)
- [ ] Captions (styles, burn-in, SRT/VTT)
- [ ] Audio clean-up (DeepFilterNet, loudness)
- [ ] Hardware export presets
- [ ] v2: auto-clips + reframing, teleprompter, storyboards/scripts (port), motion templates, B-roll, voiceover, translation
