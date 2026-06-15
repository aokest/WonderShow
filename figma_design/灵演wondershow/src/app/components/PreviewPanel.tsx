import { CameraOff } from "lucide-react";
import type { Strings } from "../i18n";

const T = {
  surface:  "#181309",
  overlay:  "#1E1810",
  border:   "#3A2E1E",
  textPrim: "#EDE8DC",
  textSec:  "#B8A882",
  textTert: "#8A7A62",
  amber:    "#C8923A",
  teal:     "#3EB5B0",
  red:      "#C84038",
};

interface PreviewPanelProps {
  cameraActive: boolean;
  isRecording: boolean;
  gestureActive: boolean;
  elapsedTime: string;
  s: Strings;
}

function HandOverlay() {
  const pts = [
    {x:50,y:60},{x:44,y:52},{x:38,y:44},{x:34,y:38},{x:30,y:34},
    {x:46,y:43},{x:44,y:36},{x:43,y:31},{x:42,y:27},
    {x:51,y:42},{x:51,y:34},{x:51,y:29},{x:51,y:25},
    {x:56,y:43},{x:57,y:36},{x:57,y:31},{x:57,y:27},
    {x:62,y:46},{x:64,y:40},{x:64,y:35},{x:64,y:31},
  ];
  return (
    <svg className="absolute inset-0 w-full h-full pointer-events-none" viewBox="0 0 100 100" preserveAspectRatio="none">
      <rect x="28" y="22" width="40" height="46" fill="none"
        stroke={T.amber} strokeWidth="0.45" strokeDasharray="2.5 1.5" opacity="0.5" rx="1.5" />
      {pts.map((p, i) => (
        <circle key={i} cx={p.x} cy={p.y} r="0.85"
          fill="rgba(237,232,220,0.72)" stroke="rgba(255,255,255,0.85)" strokeWidth="0.3" />
      ))}
    </svg>
  );
}

export function PreviewPanel({ cameraActive, isRecording, gestureActive, elapsedTime, s }: PreviewPanelProps) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 10, height: "100%", minHeight: 0 }}>

      {/* 预览：强制 16:9 */}
      <div style={{ width: "100%", aspectRatio: "16/9", flexShrink: 0, position: "relative" }}>
        <div style={{
          position: "absolute", inset: 0,
          borderRadius: 14, border: `1px solid ${T.border}`,
          background: "#050302", overflow: "hidden",
          boxShadow: `inset 0 1px 0 rgba(255,220,140,0.06), 0 0 0 1px rgba(200,146,58,0.08), 0 12px 40px rgba(0,0,0,0.75)`,
        }}>

          {isRecording && (
            <div style={{ position: "absolute", top: 0, left: 0, right: 0, height: 2, background: "rgba(40,20,5,0.5)", zIndex: 20 }}>
              <div style={{ height: "100%", background: T.red, animation: "recProgress 60s linear infinite" }} />
            </div>
          )}

          {cameraActive ? (
            <>
              <div style={{ position: "absolute", inset: 0, background: "radial-gradient(ellipse 60% 55% at 50% 72%, #2E2010 0%, #14100A 55%, #080503 100%)" }} />
              <div style={{ position: "absolute", top: "-8%", left: "16%", width: "30%", height: "60%", background: "radial-gradient(ellipse at 50% 8%, rgba(200,146,58,0.20) 0%, transparent 68%)", pointerEvents: "none" }} />
              <div style={{ position: "absolute", top: "-8%", right: "16%", width: "30%", height: "60%", background: "radial-gradient(ellipse at 50% 8%, rgba(200,146,58,0.16) 0%, transparent 68%)", pointerEvents: "none" }} />
              <div style={{ position: "absolute", bottom: 0, left: "50%", transform: "translateX(-50%)", width: "36%", height: "84%", background: "radial-gradient(ellipse at 50% 24%, #2E2010 0%, #1A1208 55%, transparent 100%)", borderRadius: "52% 52% 0 0", opacity: 0.95 }} />
              <div style={{ position: "absolute", bottom: "4%", left: "50%", transform: "translateX(-50%)", width: "58%", height: "16%", background: "radial-gradient(ellipse,rgba(200,146,58,0.14) 0%,transparent 70%)", pointerEvents: "none" }} />

              {gestureActive && <HandOverlay />}

              <div style={{ position: "absolute", top: 12, left: 12, display: "flex", alignItems: "center", gap: 6 }}>
                <div style={{ width: 6, height: 6, borderRadius: "50%", background: T.teal, flexShrink: 0, animation: isRecording ? "recPulse 1.2s ease-in-out infinite" : "none" }} />
                <span style={{ fontSize: 10, color: T.textPrim, textTransform: "uppercase", letterSpacing: "0.12em", fontWeight: 600, whiteSpace: "nowrap" }}>{s.live}</span>
              </div>

              <div style={{ position: "absolute", bottom: 12, left: 12, display: "flex", flexDirection: "column", gap: 5 }}>
                {[
                  { icon: "◈", text: gestureActive ? s.gestureZoneActive : s.gestureZoneIdle },
                  { icon: "↗", text: s.lastAction },
                  { icon: "✋", text: s.gestureDetected },
                ].map((c, i) => (
                  <div key={i} style={{
                    display: "flex", alignItems: "center", gap: 6,
                    background: "rgba(6,4,2,0.72)", border: "1px solid rgba(200,146,58,0.14)",
                    borderRadius: 7, padding: "4px 9px", backdropFilter: "blur(4px)", whiteSpace: "nowrap",
                  }}>
                    <span style={{ fontSize: 11, color: T.textTert, flexShrink: 0 }}>{c.icon}</span>
                    <span style={{ fontSize: 12, color: "#D8CEBC", fontWeight: 400 }}>{c.text}</span>
                  </div>
                ))}
              </div>
            </>
          ) : (
            <div style={{ position: "absolute", inset: 0, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 10 }}>
              <CameraOff size={32} color={T.textTert} strokeWidth={1.5} />
              <span style={{ fontSize: 14, fontWeight: 500, color: T.textSec, whiteSpace: "nowrap" }}>{s.noCam}</span>
              <span style={{ fontSize: 12, color: T.textTert, whiteSpace: "nowrap" }}>{s.noCamHint}</span>
              <button style={{ marginTop: 6, height: 30, padding: "0 14px", borderRadius: 8, background: T.overlay, border: `1px solid #5A4428`, color: "#D8CEBC", fontSize: 12, fontWeight: 500, cursor: "pointer", whiteSpace: "nowrap" }}>{s.reconnect}</button>
            </div>
          )}
        </div>
      </div>

      {/* 导演摘要条 */}
      <div style={{
        display: "flex", flexShrink: 0,
        background: T.surface, border: `1px solid ${T.border}`,
        borderRadius: 10, height: 50, overflow: "hidden",
        boxShadow: "inset 0 1px 0 rgba(255,220,140,0.04)",
      }}>
        {[
          { label: s.recModeLabel, value: s.modeCamScreen },
          { label: s.layoutLabel, value: s.layoutPiP },
          { label: s.outputTracks, value: s.outputTracksVal },
          { label: s.elapsed, value: elapsedTime, mono: true },
        ].map((cell, i, arr) => (
          <div key={i} style={{
            flex: 1, display: "flex", flexDirection: "column", justifyContent: "center",
            padding: "0 14px",
            borderRight: i < arr.length - 1 ? `1px solid ${T.border}` : "none",
          }}>
            <span style={{ fontSize: 10, color: T.textTert, textTransform: "uppercase", letterSpacing: "0.07em", fontWeight: 500, whiteSpace: "nowrap" }}>{cell.label}</span>
            <span style={{ fontSize: 13, fontWeight: 500, color: T.textPrim, fontFamily: cell.mono ? "var(--font-mono)" : "var(--font-sans)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{cell.value}</span>
          </div>
        ))}
      </div>

      <style>{`
        @keyframes recProgress{0%{width:0%}100%{width:100%}}
        @keyframes recPulse{0%,100%{opacity:1}50%{opacity:0.25}}
      `}</style>
    </div>
  );
}
