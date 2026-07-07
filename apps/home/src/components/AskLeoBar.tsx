"use client";

import { useRef, useState } from "react";
import { Monogram } from "./Monogram";
import { CardGrain } from "./CardGrain";

interface AskLeoBarProps {
  inputRef?: React.RefObject<HTMLInputElement | null>;
}

export function AskLeoBar({ inputRef }: AskLeoBarProps) {
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(false);
  const [response, setResponse] = useState<{
    summary: string;
    routed_to?: string;
    mode: string;
    error?: string;
  } | null>(null);
  const localRef = useRef<HTMLInputElement>(null);
  const ref = inputRef ?? localRef;

  async function handleSubmit() {
    if (!query.trim() || loading) return;
    setLoading(true);
    setResponse(null);
    try {
      const res = await fetch("/api/ask-leo", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query: query.trim() }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error ?? "Request failed");
      setResponse({
        summary: data.summary,
        routed_to: data.routed_to,
        mode: data.mode,
      });
    } catch (e) {
      setResponse({
        summary: "",
        mode: "error",
        error: e instanceof Error ? e.message : "Ask failed",
      });
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="ask-leo-wrap">
      <div className="ask-leo">
        <CardGrain />
        <Monogram id="leo" variant="emboss-dark" className="ask-leo-mono" />
        <input
          ref={ref}
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              void handleSubmit();
            }
          }}
          placeholder="ask leo anything, he'll route it to the right agent"
          aria-label="Ask Leo"
          disabled={loading}
        />
        <kbd className="kbd">⌘ K</kbd>
      </div>

      {(loading || response) && (
        <div className="ask-leo-response" aria-live="polite">
          {loading && <p className="ask-leo-response-text">routing…</p>}
          {!loading && response?.error && (
            <p className="ask-leo-response-text ask-leo-response-error">{response.error}</p>
          )}
          {!loading && response?.summary && (
            <>
              {response.routed_to && (
                <p className="ask-leo-response-meta">via {response.routed_to}</p>
              )}
              <p className="ask-leo-response-text">{response.summary}</p>
            </>
          )}
        </div>
      )}
    </div>
  );
}
