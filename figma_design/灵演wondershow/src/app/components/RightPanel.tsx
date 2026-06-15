import { useState } from "react";
import { RefreshCw, Play, ChevronDown, RotateCcw, ChevronRight } from "lucide-react";
import type { Strings } from "../i18n";

const T = {
  surface:   "#181309",
  overlay:   "#1E1810",
  border:    "#3A2E1E",
  borderSub: "#2C2418",
  textPrim:  "#EDE8DC",
  textSec:   "#B8A882",
  textTert:  "#8A7A62",
  amber:     "#C8923A",
  teal:      "#3EB5B0",
  red:       "#C84038",
};

function SecondaryBtn({ children, onClick, small }: { children: React.ReactNode; onClick?: () => void; small?: boolean }) {
  const [hov, setHov] = useState(false);
  return (
    <button onClick={onClick} onMouseEnter={() => setHov(true)} onMouseLeave={() => setHov(false)}
      style={{
        height: small ? 26 : 30, padding: small ? "0 10px" : "0 13px", borderRadius: 7,
        background: hov ? "linear-gradient(180deg,#5A3E18 0%,#482E10 100%)" : "linear-gradient(180deg,#4A3214 0%,#38260E 100%)",
        border: `1px solid ${hov ? "#D09840" : "#8A6428"}`,
        color: hov ? "#FFE8A0" : "#E8C870",
        fontSize: small ? 11 : 12, fontWeight: 600, cursor: "pointer",
        display: "flex", alignItems: "center", gap: 5, whiteSpace: "nowrap", flexShrink: 0,
        boxShadow: hov
          ? "inset 0 1px 0 rgba(255,230,140,0.18), 0 2px 10px rgba(0,0,0,0.45)"
          : "inset 0 1px 0 rgba(255,230,140,0.12), 0 1px 5px rgba(0,0,0,0.4)",
        transition: "all 150ms ease-out",
      }}>{children}</button>
  );
}

function SelectInput({ options, value, onChange }: { options: { label: string; value: string }[]; value: string; onChange: (v: string) => void }) {
  return (
    <div style={{ position: "relative", width: "100%" }}>
      <select value={value} onChange={(e) => onChange(e.target.value)} style={{
        width: "100%", height: 28, padding: "0 26px 0 9px", borderRadius: 7,
        background: "linear-gradient(180deg,#201A0C 0%,#181309 100%)",
        border: `1px solid #5A4428`, color: T.textPrim, fontSize: 12, fontWeight: 500,
        cursor: "pointer", outline: "none", appearance: "none",
        boxShadow: "inset 0 1px 0 rgba(255,220,140,0.05)", transition: "border-color 150ms",
      }}
        onFocus={(e) => { e.currentTarget.style.borderColor = T.amber; }}
        onBlur={(e) =>  { e.currentTarget.style.borderColor = "#5A4428"; }}
      >
        {options.map((o) => <option key={o.value} value={o.value} style={{ background: T.surface }}>{o.label}</option>)}
      </select>
      <ChevronDown size={11} color={T.textTert} style={{ position: "absolute", right: 8, top: "50%", transform: "translateY(-50%)", pointerEvents: "none" }} />
    </div>
  );
}

function Row({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, minHeight: 20 }}>
      <span style={{ fontSize: 11, color: T.textTert, whiteSpace: "nowrap", flexShrink: 0 }}>{label}</span>
      <span style={{ fontSize: 12, fontWeight: 500, color: "#CCC4B0", fontFamily: mono ? "var(--font-mono)" : "var(--font-sans)", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis", textAlign: "right" }}>{value}</span>
    </div>
  );
}

function FormLabel({ children }: { children: React.ReactNode }) {
  return <span style={{ fontSize: 10, color: T.textTert, textTransform: "uppercase", letterSpacing: "0.07em", fontWeight: 500, whiteSpace: "nowrap" }}>{children}</span>;
}

function Divider() {
  return <div style={{ height: 1, background: T.borderSub, margin: "2px -14px" }} />;
}

function Card({ title, hint, collapsed, onToggle, children }: { title: string; hint?: string; collapsed: boolean; onToggle: () => void; children: React.ReactNode }) {
  return (
    <div style={{ background: T.surface, border: `1px solid ${T.border}`, borderRadius: 12, overflow: "hidden", boxShadow: "inset 0 1px 0 rgba(255,220,140,0.05), 0 4px 18px rgba(0,0,0,0.45)", flexShrink: 0 }}>
      <button onClick={onToggle} style={{ width: "100%", height: 40, display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 14px", background: "transparent", border: "none", cursor: "pointer", borderBottom: collapsed ? "none" : `1px solid ${T.borderSub}` }}>
        <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
          <ChevronRight size={12} color={T.textTert} style={{ transform: collapsed ? "rotate(0deg)" : "rotate(90deg)", transition: "transform 200ms cubic-bezier(0.2,0.8,0.2,1)", flexShrink: 0 }} />
          <span style={{ fontSize: 12, fontWeight: 600, color: T.textPrim, whiteSpace: "nowrap" }}>{title}</span>
        </div>
        {hint && <span style={{ fontSize: 10, color: T.textTert, whiteSpace: "nowrap" }}>{hint}</span>}
      </button>
      {!collapsed && <div style={{ padding: 14, display: "flex", flexDirection: "column", gap: 10 }}>{children}</div>}
    </div>
  );
}

export function QuickStartCard({ collapsed, onToggle, isRecording, cameraActive, gestureActive, onRefreshDevices, onTestSlide, s }: {
  collapsed: boolean; onToggle: () => void; isRecording: boolean; cameraActive: boolean;
  gestureActive: boolean; onRefreshDevices: () => void; onTestSlide: () => void; s: Strings;
}) {
  return (
    <Card title={s.quickStart} hint={s.realtime} collapsed={collapsed} onToggle={onToggle}>
      <div style={{ display: "flex", flexDirection: "column", gap: 7 }}>
        <Row label={s.rehearseState} value={s.readyVal} />
        <Row label={s.recState} value={isRecording ? s.recVal : s.standbyVal} />
        <Row label={s.activeDevice} value={cameraActive ? s.deviceVal : s.noDevice} />
        <Row label={s.currentGesture} value={s.gestureDetected} />
      </div>
      <Divider />
      <div style={{ display: "flex", gap: 7 }}>
        <SecondaryBtn onClick={onRefreshDevices}><RefreshCw size={11} />{s.refreshDevices}</SecondaryBtn>
        <SecondaryBtn onClick={onTestSlide}><Play size={11} />{s.testSlide}</SecondaryBtn>
      </div>
    </Card>
  );
}

export function PresentationCard({ collapsed, onToggle, targetApp, setTargetApp, recordingMode, setRecordingMode, layout, setLayout, onOpenTestDeck, s }: {
  collapsed: boolean; onToggle: () => void; targetApp: string; setTargetApp: (v: string) => void;
  recordingMode: string; setRecordingMode: (v: string) => void; layout: string; setLayout: (v: string) => void;
  onOpenTestDeck: () => void; s: Strings;
}) {
  return (
    <Card title={s.presentSettings} hint={s.auto} collapsed={collapsed} onToggle={onToggle}>
      <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
        <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
          <FormLabel>{s.targetApp}</FormLabel>
          <SelectInput value={targetApp} onChange={setTargetApp} options={[
            { label: s.appPPT, value: "powerpoint" }, { label: s.appWPS, value: "wps" },
            { label: s.appKeynote, value: "keynote" }, { label: s.appPDF, value: "pdf" },
            { label: s.appHTML, value: "html" },
          ]} />
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
          <FormLabel>{s.recMode}</FormLabel>
          <SelectInput value={recordingMode} onChange={setRecordingMode} options={[
            { label: s.modeCam, value: "camera" }, { label: s.modeCamScreen, value: "camera-screen" },
          ]} />
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
          <FormLabel>{s.layout}</FormLabel>
          <SelectInput value={layout} onChange={setLayout} options={[
            { label: s.layoutCloseup, value: "closeup" }, { label: s.layoutPiP, value: "pip" },
            { label: s.layoutSide, value: "side" },
          ]} />
        </div>
      </div>
      <Divider />
      <SecondaryBtn onClick={onOpenTestDeck}>{s.openTestDeck}</SecondaryBtn>
    </Card>
  );
}

export function GestureCard({ collapsed, onToggle, gesturesEnabled, setGesturesEnabled, gestureActive, s }: {
  collapsed: boolean; onToggle: () => void; gesturesEnabled: boolean;
  setGesturesEnabled: (v: boolean) => void; gestureActive: boolean; s: Strings;
}) {
  const [cheatOpen, setCheatOpen] = useState(false);
  const gestures = [
    { icon: "👉", name: s.g1name, result: s.g1result },
    { icon: "👈", name: s.g2name, result: s.g2result },
    { icon: "✋", name: s.g3name, result: s.g3result },
    { icon: "👍", name: s.g4name, result: s.g4result },
  ];
  return (
    <Card title={s.gestureWorkspace} hint={s.last5min} collapsed={collapsed} onToggle={onToggle}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <span style={{ fontSize: 12, color: "#C8BEAC", whiteSpace: "nowrap" }}>{s.enableGesture}</span>
        <button onClick={() => setGesturesEnabled(!gesturesEnabled)} style={{
          width: 36, height: 20, borderRadius: 10, flexShrink: 0,
          background: gesturesEnabled ? "linear-gradient(180deg,#D09838 0%,#A07020 100%)" : "linear-gradient(180deg,#2A2016 0%,#1E180C 100%)",
          border: `1px solid ${gesturesEnabled ? "#B07830" : T.border}`,
          cursor: "pointer", position: "relative",
          boxShadow: gesturesEnabled ? "inset 0 1px 0 rgba(255,230,140,0.2),0 1px 4px rgba(200,150,40,0.3)" : "inset 0 1px 0 rgba(255,220,140,0.03)",
          transition: "all 240ms cubic-bezier(0.2,0.8,0.2,1)",
        }}>
          <span style={{ position: "absolute", top: 2, left: gesturesEnabled ? 18 : 2, width: 14, height: 14, borderRadius: "50%", background: gesturesEnabled ? "#FFF0C8" : "#5A4E3C", boxShadow: gesturesEnabled ? "0 0 6px rgba(255,210,80,0.5)" : "0 1px 4px rgba(0,0,0,0.5)", transition: "left 240ms cubic-bezier(0.2,0.8,0.2,1)" }} />
        </button>
      </div>
      <Divider />
      <div style={{ display: "flex", flexDirection: "column", gap: 7 }}>
        <Row label={s.recogState} value={gestureActive ? s.activeVal : s.standbyVal} />
        <Row label={s.session} value={s.sessionVal} />
        <Row label={s.engine} value={s.engineVal} mono />
        <Row label={s.zone} value={s.zoneVal} />
      </div>
      <Divider />
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <SecondaryBtn>{s.calibrate}</SecondaryBtn>
        <button onClick={() => setCheatOpen(!cheatOpen)} style={{
          background: "none", border: "none", cursor: "pointer", color: T.textTert,
          fontSize: 11, display: "flex", alignItems: "center", gap: 4, padding: 0, whiteSpace: "nowrap", transition: "color 150ms",
        }}
          onMouseEnter={(e) => { e.currentTarget.style.color = T.textSec; }}
          onMouseLeave={(e) => { e.currentTarget.style.color = T.textTert; }}
        >
          <ChevronDown size={11} style={{ transform: cheatOpen ? "rotate(180deg)" : "none", transition: "transform 150ms" }} />
          {s.cheatsheet}
        </button>
      </div>
      {cheatOpen && (
        <div style={{ display: "flex", flexDirection: "column" }}>
          {gestures.map((g, i) => (
            <div key={i} style={{ display: "flex", alignItems: "center", gap: 7, height: 26, borderTop: i > 0 ? `1px solid ${T.borderSub}` : "none" }}>
              <span style={{ fontSize: 12, width: 18, textAlign: "center", flexShrink: 0 }}>{g.icon}</span>
              <span style={{ fontSize: 11, color: T.textSec, flex: 1, whiteSpace: "nowrap" }}>{g.name}</span>
              <span style={{ fontSize: 11, color: T.textTert, whiteSpace: "nowrap" }}>{g.result}</span>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}

export function DevicesCard({ collapsed, onToggle, onRescan, s }: { collapsed: boolean; onToggle: () => void; onRescan: () => void; s: Strings }) {
  const [device, setDevice] = useState("facetime");
  return (
    <Card title={s.devicesTitle} hint={s.autoScan} collapsed={collapsed} onToggle={onToggle}>
      <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
        <FormLabel>{s.inputDevice}</FormLabel>
        <div style={{ display: "flex", gap: 7 }}>
          <div style={{ flex: 1 }}>
            <SelectInput value={device} onChange={setDevice} options={[
              { label: s.dev1, value: "facetime" }, { label: s.dev2, value: "logitech" },
              { label: s.dev3, value: "iphone" }, { label: s.dev4, value: "obs" },
            ]} />
          </div>
          <SecondaryBtn onClick={onRescan} small><RotateCcw size={10} />{s.rescan}</SecondaryBtn>
        </div>
      </div>
      <Divider />
      <div style={{ display: "flex", flexDirection: "column", gap: 7 }}>
        <Row label={s.statusLabel} value={s.statusVal} />
        <Row label={s.deviceDetail} value={s.deviceDetailVal} mono />
        <Row label={s.inputsFound} value={s.inputsVal} />
        <Row label={s.transport} value={s.transportVal} mono />
      </div>
    </Card>
  );
}
