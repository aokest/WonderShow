import { useState, useRef, useEffect } from "react";
import { ChevronRight, Github, User, X } from "lucide-react";
import type { Strings } from "../i18n";

const T = {
  bg:       "#0D0A07",
  surface:  "#1E1810",
  border:   "#3A2E1E",
  borderSub:"#2C2418",
  textPrim: "#EDE8DC",
  textSec:  "#B8A882",
  textTert: "#8A7A62",
  amber:    "#C8923A",
  teal:     "#3EB5B0",
};

export function Footer({ s }: { s: Strings }) {
  const [diagOpen, setDiagOpen]   = useState(false);
  const [aboutOpen, setAboutOpen] = useState(false);
  const aboutRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!aboutOpen) return;
    const handler = (e: MouseEvent) => {
      if (aboutRef.current && !aboutRef.current.contains(e.target as Node)) setAboutOpen(false);
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [aboutOpen]);

  return (
    <div style={{ borderTop: `1px solid ${T.border}`, background: T.bg, flexShrink: 0, position: "relative", boxShadow: "0 -1px 0 rgba(255,220,140,0.02)" }}>

      {/* 「关于」弹出卡 */}
      {aboutOpen && (
        <div ref={aboutRef} style={{
          position: "absolute", bottom: 48, left: 16, width: 220,
          background: T.surface, border: `1px solid ${T.border}`, borderRadius: 12,
          padding: "14px 16px", zIndex: 50, display: "flex", flexDirection: "column", gap: 10,
          boxShadow: "0 -8px 32px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,220,140,0.07)",
        }}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
            <span style={{ fontSize: 12, fontWeight: 600, color: T.textPrim }}>{s.aboutTitle}</span>
            <button onClick={() => setAboutOpen(false)} style={{ background: "none", border: "none", cursor: "pointer", padding: 2, color: T.textTert, display: "flex", alignItems: "center", borderRadius: 4, transition: "color 150ms" }}
              onMouseEnter={(e) => { e.currentTarget.style.color = T.textPrim; }}
              onMouseLeave={(e) => { e.currentTarget.style.color = T.textTert; }}>
              <X size={13} />
            </button>
          </div>
          <div style={{ height: 1, background: T.borderSub }} />
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <User size={13} color={T.amber} strokeWidth={1.75} style={{ flexShrink: 0 }} />
              <div>
                <div style={{ fontSize: 10, color: T.textTert, textTransform: "uppercase", letterSpacing: "0.07em", marginBottom: 1 }}>{s.authorLabel}</div>
                <div style={{ fontSize: 13, fontWeight: 600, color: T.textPrim }}>{s.authorVal}</div>
              </div>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
              <Github size={13} color={T.amber} strokeWidth={1.75} style={{ flexShrink: 0 }} />
              <div>
                <div style={{ fontSize: 10, color: T.textTert, textTransform: "uppercase", letterSpacing: "0.07em", marginBottom: 1 }}>GitHub</div>
                <a href="https://github.com/aokest" target="_blank" rel="noopener noreferrer"
                  style={{ fontSize: 12, fontWeight: 500, color: T.amber, fontFamily: "var(--font-mono)", textDecoration: "none", transition: "color 150ms" }}
                  onMouseEnter={(e) => { (e.currentTarget as HTMLAnchorElement).style.color = "#E0B060"; }}
                  onMouseLeave={(e) => { (e.currentTarget as HTMLAnchorElement).style.color = T.amber; }}>
                  github.com/aokest
                </a>
              </div>
            </div>
          </div>
          <div style={{ height: 1, background: T.borderSub }} />
          <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
            <span style={{ fontSize: 11, color: T.textTert, fontFamily: "var(--font-mono)" }}>v0.6.0</span>
            <span style={{ fontSize: 11, color: T.textTert }}>WonderShow</span>
          </div>
        </div>
      )}

      {/* 主行 */}
      <div style={{ height: 40, display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 20px" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 10, flexShrink: 0 }}>
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: T.textTert, whiteSpace: "nowrap" }}>{s.version}</span>
          <button onClick={() => { setAboutOpen(!aboutOpen); setDiagOpen(false); }}
            style={{ background: "none", border: "none", cursor: "pointer", padding: 0, fontSize: 11, color: aboutOpen ? T.amber : T.textSec, whiteSpace: "nowrap", transition: "color 150ms" }}
            onMouseEnter={(e) => { e.currentTarget.style.color = T.amber; }}
            onMouseLeave={(e) => { e.currentTarget.style.color = aboutOpen ? T.amber : T.textSec; }}>
            {s.about}
          </button>
        </div>

        <button onClick={() => { setDiagOpen(!diagOpen); setAboutOpen(false); }}
          style={{ background: "none", border: "none", cursor: "pointer", color: diagOpen ? T.textSec : T.textTert, fontSize: 11, display: "flex", alignItems: "center", gap: 5, padding: 0, whiteSpace: "nowrap", transition: "color 150ms" }}
          onMouseEnter={(e) => { e.currentTarget.style.color = T.textSec; }}
          onMouseLeave={(e) => { e.currentTarget.style.color = diagOpen ? T.textSec : T.textTert; }}>
          <ChevronRight size={12} style={{ transform: diagOpen ? "rotate(90deg)" : "rotate(0deg)", transition: "transform 150ms ease-out" }} />
          {s.advDiag}
        </button>

        <div style={{ display: "flex", alignItems: "center", gap: 6, flexShrink: 0 }}>
          <div style={{ width: 6, height: 6, borderRadius: "50%", background: T.teal, flexShrink: 0 }} />
          <span style={{ fontFamily: "var(--font-mono)", fontSize: 11, color: T.textSec, whiteSpace: "nowrap" }}>{s.connectedStatus}</span>
        </div>
      </div>

      {/* 诊断展开 */}
      {diagOpen && (
        <div style={{ borderTop: `1px solid ${T.borderSub}`, padding: "12px 20px 14px", display: "flex", flexDirection: "column", gap: 10 }}>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "8px 32px" }}>
            {[
              { label: s.accessPerm, value: s.accessVal },
              { label: s.chromeAuto, value: s.chromeVal },
              { label: s.scanSummary, value: s.scanVal },
              { label: s.examples, value: s.examplesVal },
            ].map((item, i) => (
              <div key={i} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
                <span style={{ fontSize: 11, color: T.textTert, whiteSpace: "nowrap" }}>{item.label}</span>
                <span style={{ fontSize: 11, color: "#C8BEAC", fontFamily: "var(--font-mono)", whiteSpace: "nowrap" }}>{item.value}</span>
              </div>
            ))}
          </div>
          <div style={{ display: "flex", gap: 7 }}>
            {[s.permBtn, s.requestBtn, s.chromeBtn, s.refreshBtn].map((label) => (
              <button key={label} style={{ height: 24, padding: "0 10px", borderRadius: 6, background: "transparent", border: `1px solid ${T.borderSub}`, color: T.textTert, fontSize: 11, cursor: "pointer", whiteSpace: "nowrap", transition: "color 150ms, border-color 150ms" }}
                onMouseEnter={(e) => { e.currentTarget.style.color = T.textSec; e.currentTarget.style.borderColor = T.border; }}
                onMouseLeave={(e) => { e.currentTarget.style.color = T.textTert; e.currentTarget.style.borderColor = T.borderSub; }}>
                {label}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
