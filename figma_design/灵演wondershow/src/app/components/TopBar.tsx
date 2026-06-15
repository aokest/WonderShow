import { Camera, Hand, Monitor, Circle, Square } from "lucide-react";
import { ImageWithFallback } from "./figma/ImageWithFallback";
import logoSrc from "../../imports/image.png";
import type { Lang, Strings } from "../i18n";

const T = {
  bg:       "#0D0A07",
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

interface TopBarProps {
  isRecording: boolean;
  cameraActive: boolean;
  gestureActive: boolean;
  targetApp: string;
  onToggleRecord: () => void;
  onRehearseClick: () => void;
  lang: Lang;
  setLang: (l: Lang) => void;
  s: Strings;
}

function StatusPill({ icon, label, value, active, isRec }: {
  icon: React.ReactNode; label: string; value: string; active: boolean; isRec?: boolean;
}) {
  const dotColor = isRec && active ? T.red : active ? T.teal : "transparent";
  const dotBorder = active ? "none" : `1.5px solid ${T.textTert}`;
  return (
    <div style={{
      height: 30, display: "flex", alignItems: "center", gap: 7, padding: "0 11px",
      background: T.surface, border: `1px solid ${T.border}`, borderRadius: 8,
      boxShadow: "inset 0 1px 0 rgba(255,220,140,0.04)",
      flexShrink: 0, whiteSpace: "nowrap",
    }}>
      <div style={{
        width: 6, height: 6, borderRadius: "50%", flexShrink: 0,
        background: dotColor, border: dotBorder,
        animation: isRec && active ? "recPulse 1.2s ease-in-out infinite" : "none",
      }} />
      <span style={{ color: T.textTert, display: "flex", flexShrink: 0 }}>{icon}</span>
      <span style={{ fontSize: 10, color: T.textSec, textTransform: "uppercase", letterSpacing: "0.07em", fontWeight: 500, flexShrink: 0 }}>{label}</span>
      <span style={{ fontSize: 12, color: T.textPrim, fontWeight: 500, flexShrink: 0 }}>{value}</span>
    </div>
  );
}

const LANGS: Lang[] = ["zh-CN", "EN", "zh-TW"];
const LANG_LABELS: Record<Lang, string> = { "zh-CN": "简", "EN": "EN", "zh-TW": "繁" };

export function TopBar({ isRecording, cameraActive, gestureActive, targetApp, onToggleRecord, onRehearseClick, lang, setLang, s }: TopBarProps) {
  return (
    <div style={{
      height: 56, display: "flex", alignItems: "center", justifyContent: "space-between",
      padding: "0 20px", flexShrink: 0,
      background: T.bg, borderBottom: `1px solid ${T.border}`,
      boxShadow: "0 1px 0 rgba(255,220,140,0.03)",
    }}>

      {/* 左：Logo + 品牌文字 */}
      <div style={{ display: "flex", alignItems: "center", gap: 10, flexShrink: 0 }}>
        {/* App 图标 */}
        <div style={{
          width: 34, height: 34, borderRadius: 9, overflow: "hidden", flexShrink: 0,
          boxShadow: `0 0 0 1px ${T.border}, 0 2px 10px rgba(200,146,58,0.22)`,
        }}>
          <ImageWithFallback src={logoSrc} alt="WonderShow Logo"
            style={{ width: "100%", height: "100%", objectFit: "cover", display: "block", transform: "scale(1.14)", transformOrigin: "center center" }} />
        </div>

        {/* 「灵演」：Noto Serif SC，与 Cinzel 同族高对比度衬线气质 */}
        <div style={{ display: "flex", flexDirection: "column", gap: 0, justifyContent: "center" }}>
          <span style={{
            fontFamily: "'Noto Serif SC', 'Noto Serif', serif",
            fontWeight: 700,
            fontSize: 17,
            color: T.textPrim,
            letterSpacing: "0.06em",
            whiteSpace: "nowrap",
            lineHeight: 1,
            textShadow: "0 0 20px rgba(200,146,58,0.22)",
          }}>{s.appName}</span>
        </div>

        {/* 竖线分隔 */}
        <div style={{ width: 1, height: 26, background: T.border, flexShrink: 0 }} />

        {/* WONDERSHOW + STUDIO 双行 */}
        <div style={{ display: "flex", flexDirection: "column", gap: 2, justifyContent: "center" }}>
          <span style={{
            fontFamily: "'Cinzel', serif",
            fontWeight: 700,
            fontSize: 13,
            color: T.textPrim,
            letterSpacing: "0.18em",
            whiteSpace: "nowrap",
            lineHeight: 1,
            textShadow: "0 0 24px rgba(200,146,58,0.28)",
          }}>WONDERSHOW</span>
          <span style={{
            fontFamily: "var(--font-mono)",
            fontWeight: 500,
            fontSize: 9,
            color: T.textTert,
            textTransform: "uppercase",
            letterSpacing: "0.26em",
            whiteSpace: "nowrap",
            lineHeight: 1,
          }}>{s.studio}</span>
        </div>
      </div>

      {/* 中：状态胶囊 */}
      <div style={{ display: "flex", gap: 8, flexShrink: 0 }}>
        <StatusPill icon={<Camera size={12} strokeWidth={1.75} />} label={s.camera} value={cameraActive ? s.connected : s.disconnected} active={cameraActive} />
        <StatusPill icon={<Hand size={12} strokeWidth={1.75} />} label={s.gesture} value={gestureActive ? s.recognizing : s.standby} active={gestureActive} />
        <StatusPill icon={<Monitor size={12} strokeWidth={1.75} />} label={s.target} value={targetApp} active={true} />
        <StatusPill icon={<Circle size={12} strokeWidth={1.75} />} label={s.rec} value={isRecording ? s.recording : s.ready} active={isRecording} isRec />
      </div>

      {/* 右：语言切换 + 操作按钮 */}
      <div style={{ display: "flex", alignItems: "center", gap: 12, flexShrink: 0 }}>

        {/* 语言切换器 */}
        <div style={{
          display: "flex",
          background: T.surface,
          border: `1px solid ${T.border}`,
          borderRadius: 8,
          overflow: "hidden",
          height: 28,
          boxShadow: "inset 0 1px 0 rgba(255,220,140,0.04)",
        }}>
          {LANGS.map((l, i) => (
            <button key={l} onClick={() => setLang(l)} style={{
              width: 36, height: "100%", border: "none",
              borderLeft: i > 0 ? `1px solid ${T.border}` : "none",
              background: lang === l
                ? "linear-gradient(180deg,#4A3214 0%,#38260E 100%)"
                : "transparent",
              color: lang === l ? "#E8C870" : T.textTert,
              fontSize: 11, fontWeight: lang === l ? 700 : 500,
              cursor: "pointer", whiteSpace: "nowrap",
              letterSpacing: l === "EN" ? "0.02em" : "0.04em",
              transition: "all 150ms ease-out",
            }}
              onMouseEnter={(e) => { if (lang !== l) e.currentTarget.style.color = T.textSec; }}
              onMouseLeave={(e) => { if (lang !== l) e.currentTarget.style.color = T.textTert; }}
            >{LANG_LABELS[l]}</button>
          ))}
        </div>

        {/* 演练 */}
        <button onClick={onRehearseClick} style={{
          height: 34, padding: "0 18px", borderRadius: 8, cursor: "pointer",
          background: "linear-gradient(180deg, #4A3214 0%, #38260E 100%)",
          border: "1px solid #8A6428", color: "#E8C870",
          fontSize: 13, fontWeight: 600, whiteSpace: "nowrap",
          boxShadow: "inset 0 1px 0 rgba(255,230,140,0.12), 0 1px 5px rgba(0,0,0,0.4)",
          transition: "all 150ms ease-out",
        }}
          onMouseEnter={(e) => {
            e.currentTarget.style.background = "linear-gradient(180deg, #5A3E18 0%, #482E10 100%)";
            e.currentTarget.style.borderColor = "#D09840";
            e.currentTarget.style.color = "#FFE8A0";
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.background = "linear-gradient(180deg, #4A3214 0%, #38260E 100%)";
            e.currentTarget.style.borderColor = "#8A6428";
            e.currentTarget.style.color = "#E8C870";
          }}
        >{s.rehearse}</button>

        {/* 录制 / 停止 */}
        <button onClick={onToggleRecord} style={{
          height: 34, padding: "0 20px", borderRadius: 8, cursor: "pointer",
          background: isRecording
            ? "linear-gradient(180deg, #8A2820 0%, #6A1C16 100%)"
            : "linear-gradient(180deg, #D84840 0%, #B83428 100%)",
          border: `1px solid ${isRecording ? "#6A1E1A" : "#E05040"}`,
          color: "#fff", fontSize: 13, fontWeight: 700,
          display: "flex", alignItems: "center", gap: 8, whiteSpace: "nowrap",
          boxShadow: isRecording
            ? "inset 0 1px 0 rgba(255,255,255,0.06), 0 2px 6px rgba(0,0,0,0.5)"
            : "inset 0 1px 0 rgba(255,255,255,0.18), 0 3px 12px rgba(200,60,48,0.45)",
          letterSpacing: "0.02em", transition: "filter 150ms",
        }}
          onMouseEnter={(e) => { e.currentTarget.style.filter = "brightness(1.12)"; }}
          onMouseLeave={(e) => { e.currentTarget.style.filter = "none"; }}
        >
          {isRecording
            ? <><Square size={11} fill="white" strokeWidth={0} />{s.stopRec}</>
            : <><span style={{ width: 7, height: 7, borderRadius: "50%", background: "#fff", display: "inline-block", flexShrink: 0, boxShadow: "0 0 6px rgba(255,255,255,0.6)" }} />{s.startRec}</>
          }
        </button>
      </div>

      <style>{`@keyframes recPulse{0%,100%{opacity:1}50%{opacity:0.2}}`}</style>
    </div>
  );
}
