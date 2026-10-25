# 03: The brain: models, routing, hardware tiers, autonomy

## The Kimi reality check

You want super-advanced local models like the new Kimi. Here's the situation as of 25 Oct 2026:

| Model | Released | Size | Can it run on a Mac? |
|---|---|---|---|
| **Kimi K3.1 Pro** | 23–24 Oct 2026 (API live; open weights promised 4 Nov) | ~2.8T total params, ~104B active (MoE), 1M context | **No**, not on any single Mac. At ~4-bit that's well over 1 TB of weights. It would need a cluster of 512 GB Mac Studios |
| **Kimi K3** | Jul 2026 (weights released) | ~2.8T params | Same as above |
| **Kimi K2.6** | Apr 2026 (open weights) | ~1T total, 32B active, 256K context | Only on a **512 GB Mac Studio** at aggressive 1.8–2-bit quantisation (~240–350 GB), or **4× Mac Studios with exo over Thunderbolt 5 RDMA** (macOS 26.2+) at ~25 tok/s single-user. That's roughly US$40k (A$60k+) of hardware |
| **Kimi Linear** | Oct 2025 | 48B total, 3B active | Yes on 32 GB+ at 4-bit, but it's older and not the "new Kimi" |

**So the plan is:**
1. **Local everyday brain:** the best small and medium open models that fit the user's Mac (currently the **Qwen 3.5 / 3.6** family, **Gemma 4**, and **Apple's on-device Foundation Model**).
2. **Cloud big brain (optional, consented):** **Kimi K3.x via Moonshot's API or OpenRouter** (around US$3 per M input / US$15 per M output tokens for K3; check live pricing), plus Claude, Gemini, GPT and others. Use it for deep research, strategy, long documents and hard coding.
3. **Home big brain (power users):** point 11am at a home Mac Studio, an exo cluster, or any OpenAI-compatible server (LM Studio, Ollama, vLLM). It counts as "local" for privacy because it never leaves the user's network.

**"Add more models"** is built in: providers are plugins, and the model registry updates remotely, so when the next Kimi, Qwen or Gemma lands you ship a registry update, not an app update.

---

## Provider layer

```rust
#[async_trait]
trait ModelProvider {
    fn id(&self) -> ProviderId;
    fn capabilities(&self) -> Capabilities;      // context_len, tools, vision, json_schema, speed_tps, cost, privacy_class
    async fn complete(&self, req: CompletionRequest) -> Result<CompletionStream>;   // streaming, tools, structured output
    async fn embed(&self, req: EmbedRequest) -> Result<Vec<Vector>>;
}
```

| Provider | Where it runs | Implementation | Notes |
|---|---|---|---|
| **Apple Foundation Models** | On-device (Neural Engine/GPU), plus **Private Cloud Compute** | Swift (`FoundationModels`), via UniFFI callback | Free. Tool calling and guided (structured) generation. Small model (~3B) with a **small context window (4K tokens in the 26 release; check 27)**. macOS 27 adds image input, Dynamic Profiles, a Core Spotlight RAG tool, and **free PCC access for Small Business Program developers under 2M first-time downloads**. Needs Apple Intelligence enabled. Great for classification, short rewrites, extraction |
| **MLX** | On-device GPU | Swift `mlx-swift-lm` in **ModelHost.xpc** | Fastest local path on Apple Silicon. Loads MLX-format models from Hugging Face. Tool calling, embeddings, VLMs, LoRA |
| **llama.cpp (GGUF)** | On-device | `llama-cpp-2` crate or a bundled `llama-server` | Fallback for models without MLX builds. Huge model coverage |
| **OpenAI-compatible HTTP** | Anywhere | Rust `reqwest` | **One adapter covers Moonshot (Kimi), OpenRouter, Together, Groq, DeepSeek, LM Studio, Ollama, exo, vLLM and Jan.** User enters base URL + key + model id |
| **Anthropic** | Cloud | Rust HTTP | Claude models (strong agentic/tool use, coding) |
| **Google** | Cloud | Rust HTTP | Gemini (long context, vision) |
| **Speech (STT)** | On-device | WhisperKit (Argmax OSS), in ModelHost | Always local. SpeakerKit for diarisation |
| **Speech (TTS)** | On-device | `AVSpeechSynthesizer` (+ Personal Voice), Kokoro via `mlx-audio` on higher tiers | Always local |
| **Vision/OCR** | On-device | Apple Vision | Always local, free, fast |
| **Image generation** | On-device (Tier C+) or cloud | `mflux` (FLUX.2 etc. on MLX) as a helper, or cloud APIs | Heavy. See Robert |

**Optional unification:** macOS 27's Foundation Models framework accepts *any* model conforming to its LanguageModel protocol (Apple, Claude, Gemini, custom). You could implement MLX and HTTP providers as `LanguageModel`s and use Apple's session, tools and guided-generation API everywhere on the Swift side. **Recommendation:** keep the router in Rust (portable, testable, and the iPhone shares it). Use the Swift `LanguageModel` protocol only as an adapter for Apple's model. Re-evaluate when Apple open-sources the framework (announced for late summer 2026).

---

## Model registry (remotely updatable)

`registry/models.json` (signed, fetched weekly, pinned SHA-256 for downloads):
```json
{
  "id": "qwen3.6-35b-a3b-mlx-4bit",
  "family": "qwen3.6", "params_total_b": 35, "params_active_b": 3,
  "format": "mlx", "quant": "4bit", "disk_gb": 20, "ram_gb_min": 24,
  "context": 131072, "tools": true, "vision": false, "thinking_modes": true,
  "licence": "apache-2.0",
  "source": "hf://mlx-community/…", "sha256": "…",
  "roles": ["medium", "coder", "large.local"],
  "tiers": ["C", "D", "E"],
  "bench": { "m4_pro_24": { "tps": 60 }, "m5_air_16": null }
}
```
The **Model manager** (Settings › Brain, also inside Johnny) shows: recommended models for this Mac, downloaded models with disk use, a **"benchmark on this Mac"** button (measures tok/s and time-to-first-token), "add custom" (Hugging Face repo id or OpenAI-compatible endpoint), and per-agent overrides.

---

## Task classes and routing

Agents never name a model. They ask for a **task class**. The router picks a model using the hardware tier, user policy, data class, budget and online status.

| Task class | Examples | Default route |
|---|---|---|
| `classify.small` | Triage lane, intent routing, "is this a lead?", categorise transaction | Rules/embeddings first, then Apple FM or a 2–4B local model |
| `extract.small` | Dates, amounts, commitments, entities from text | Apple FM guided generation / 4B local with JSON schema |
| `summarise.medium` | Thread summary, page summary, meeting notes | Best local medium model (9B–35B MoE) |
| `draft.medium` | Email replies, posts, rewrites | Local medium (voice exemplars via RAG); cloud if user allows and quality mode is on |
| `reason.large` | Strategy, research synthesis, planning multi-agent projects, hard analysis | Cloud large (Kimi K3.x / Claude) if consented, else best local + "deeper overnight" option |
| `code.large` | Johnny: spec diffs, mini-apps, scripts | Local coder (Qwen 3.6 35B-A3B on Tier C+) or cloud (Kimi K2.7 Code / Claude) |
| `vision.small` | Screenshot understanding, receipt layout, design critique (light) | Apple FM (image input, macOS 27) / Vision framework / local VLM |
| `vision.large` | Design critique, chart reading | Local VLM on Tier D+ (Gemma 4 / Qwen 3.6 27B) or cloud |
| `embed` | All semantic search | **Always local** |
| `transcribe` | Voice, meetings, video | **Always local** (WhisperKit) |

### Routing policy (pseudo)
```
candidates = registry.models.filter(role ∈ task_class.roles, tier fits, downloaded or downloadable)
if data_class in user.local_only_classes or offline: candidates = candidates.local()
if task.tainted and task.wants_tools: use reader/actor split
score = quality_weight·quality + speed_weight·speed − cost_weight·cost   (weights from "Quality / Balanced / Saver" mode)
pick best; if it fails or is too slow → fall back down the chain; log to model_calls
```

### User-facing controls (simple)
- **Brain mode:** *On-device only* · *Balanced* (default: local first, cloud for `reason.large` with a one-time consent per agent) · *Best quality* (cloud wherever allowed).
- **Per agent:** "George: never use cloud" (default for finance).
- **Monthly cloud budget** with a hard cap and a warning at 80%.
- **Keys:** bring your own (Moonshot, OpenRouter, Anthropic, Google, OpenAI) or buy **11am Cloud credits** later (see [business](./08-shipping-and-business.md#cloud-brain-economics)).

---

## Hardware tiers

Detected at first launch (chip, unified memory, free disk, Apple Intelligence availability) and re-checked on upgrade. **Minimum: Apple Silicon (M1 or later), macOS 26 Tahoe.** Use macOS 27 features when available.

| Tier | Typical Mac | Local LLMs (examples, Oct 2026) | What runs locally | What goes cloud or overnight |
|---|---|---|---|---|
| **A** | 8 GB M1/M2 Air | Apple FM; **Gemma 4 E2B** (~1.5 GB) or **Qwen 3.5 4B** 4-bit (~2.5–3 GB) | Classify, extract, short rewrites, embeddings (small), OCR, transcription (Whisper small/base), search, all non-AI features | Drafting long replies, summarising long threads, research, strategy, code, image generation |
| **B** | 16 GB (incl. M5 Air base) | **Qwen 3.5 9B** 4-bit (~6 GB) or Gemma 4 12B | Plus everyday drafting, summaries, page Q&A, meeting notes (post-meeting) | Research synthesis, strategy, big code, image generation |
| **C** | 24–36 GB (M-Pro) | **Qwen 3.6 35B-A3B** 4-bit (~19–21 GB, MoE, fast) | Plus good drafting, research reading, coding, live meeting notes | Frontier-level reasoning, long-doc synthesis if wanted; image gen is slow but possible |
| **D** | 48–64 GB | Qwen 3.6 27B dense (~17 GB) + a small model resident; local VLM | Plus vision critique, image generation (mflux), concurrent models | Only "best quality" tasks |
| **E** | 96–192 GB+ (Max/Ultra/Studio) | Larger open models (100B+ class) | Nearly everything. Can serve the iPhone and other Macs as a **home brain** | Optional |
| **F** | 512 GB Studio or an exo cluster | Kimi K2.6 (1T) quantised; Kimi K3.x needs a multi-Studio cluster | Everything, including frontier-class open models | Nothing |

*Model picks will change, which is why they live in the registry and not in code. The tiers are about memory budgets: Tier A keeps ~3 GB for the model, Tier B ~6–8 GB, Tier C ~20 GB.*

**Tier A/B tricks:** speculative "quick answer now, better answer later" (local small gives a quick draft, the overnight or cloud pass improves it); summarise-then-reason (chunk with a small model, reason over summaries); prefer Apple FM for anything under ~3K tokens of context.

---

## How AI is involved: the patterns

Every brief uses these patterns. Using the same ones everywhere makes the suite feel coherent.

| Pattern | What it is | Example |
|---|---|---|
| **Ambient enrichment** | AI runs on new data automatically and adds structure: summaries, tags, entities, dates, lanes | Marc labels every email with lane + reason; Bolton extracts terms from contracts |
| **Draft-for-approval** | AI prepares the thing; the human approves, edits or rejects | Email replies, reschedule notes, invoices chasers, social posts |
| **Inline assist** | AI inside the editor, on selection or ⌘J | William rewrite; George "formula from English"; Johnny "explain this error" |
| **Ask anything (scoped)** | The Ask bar, scoped to the current app/selection/document | "What did Sarah say about pricing?" inside Marc |
| **Background job** | Long-running multi-step work with progress in the notch | James research; Cole auto-clips; George month-end |
| **Watch & alert** | Monitors with thresholds | James competitor page changes; George runway below 6 months; Marc VIP replies |
| **Brief** | Periodic summaries over the event log | Morning, the 11am check-in, evening, weekly review |
| **Teach-back** | User corrections become rules and examples | "Not a lead" → Conner's classifier example; edited drafts → William's voice exemplars |
| **Tune** | Change the software itself in plain English | "Add a column…", "Every Friday…" (Johnny) |

### Context assembly (what the model sees)
```
[system]   agent persona + rules (manifest + spec instructions + user rules)
[context]  Bolton context pack (entities, relevant memories, decisions; summarised to fit tier budget)
[recent]   relevant recent events (what the team did that matters here)
[task]     the user ask / trigger payload (untrusted content wrapped & labelled)
[tools]    allowed tools for this agent and job (policy-filtered)
[format]   JSON schema for structured output when applicable
```
Bolton owns **context packs**: a function that, given a task and entity set, returns the most relevant memories and sources within a token budget. This is the existing `/api/context` concept.

### Learning from the user (without training a giant model)
1. **Rules:** explicit ("never draft replies to newsletters") stored as spec instructions.
2. **Examples:** corrections stored as few-shot examples retrieved by similarity.
3. **Preferences:** Bolton memories ("prefers short replies to vendors").
4. **Personal adapters (Tier C+, opt-in, later):** LoRA fine-tuning on the user's accepted and edited drafts with **MLX** (`mlx-lm` supports LoRA), producing a small adapter file for William's voice. Train overnight on charger. Never needed for v1.

---

## Autonomy levels

Per agent, per action kind. Set in Settings (not by specs and not by agents).

| Level | Name | Behaviour | Default for |
|---|---|---|---|
| **L0** | Suggest | Shows a suggestion; does nothing | Anything new |
| **L1** | Draft | Prepares it and queues it in **Approvals** | Send email/message, calendar changes involving others, payments-related, posting, file deletes/moves |
| **L2** | Act & tell | Does it, logs it, includes it in the next brief, undoable | Labelling, filing, archiving newsletters, creating tasks, internal notes |
| **L3** | Act quietly | Does it, logs it, no mention | Indexing, enrichment, summaries, embeddings |

**Hard rules, whatever the settings:** irreversible actions (permanent delete, payments) and actions in tainted jobs always need approval. Bulk actions over N items always show a preview. New autonomy grants expire if unused for 90 days (Leo asks).

**Approvals UX:** one queue across all agents, in the notch, a window, the iPhone and notifications. Each card has *Approve*, *Edit*, *Reject (why?)* and *Always allow this kind* (which offers to raise the autonomy level).

---

## Evals (keep the brain honest)

| Agent | Eval | Metric |
|---|---|---|
| Leo | Routing set (300 asks labelled with agent(s)) | Top-1 accuracy, multi-agent recall |
| Marc | Triage set from your own inbox (anonymised) | Precision/recall per lane; "needs you" recall must be ≥ 0.95 |
| Bolton | Retrieval set ("find the Acme contract") | Recall@5, MRR, time to answer |
| James | Report faithfulness | % of claims with a supporting quote in a cited source |
| William | Voice | Similarity to held-out real writing; blind preference tests |
| George | Receipts/transactions | Field-level F1 (amount, date, vendor, GST) |
| Johnny | Spec diffs | Schema-valid rate, "did what was asked" human score, rollback rate |
| All | Prompt-injection suite | 0 unapproved external actions |

Run evals for each model in the registry on reference hardware so the router's quality scores are measured, not guessed.
