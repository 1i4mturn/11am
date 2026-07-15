"use client";

import { useEffect } from "react";

/** Dark cursor lamp - soft graphite wash following the pointer */
export function CursorLamp() {
  useEffect(() => {
    const lamp = document.getElementById("am-cursor-lamp");
    if (!lamp) return;

    const onMove = (e: PointerEvent) => {
      lamp.style.setProperty("--am-mx", `${e.clientX}px`);
      lamp.style.setProperty("--am-my", `${e.clientY}px`);
    };

    window.addEventListener("pointermove", onMove, { passive: true });
    return () => window.removeEventListener("pointermove", onMove);
  }, []);

  return <div id="am-cursor-lamp" className="am-cursor-lamp" aria-hidden="true" />;
}
