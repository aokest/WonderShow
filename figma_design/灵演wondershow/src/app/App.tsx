import { useState, useEffect } from "react";
import { TopBar } from "./components/TopBar";
import { PreviewPanel } from "./components/PreviewPanel";
import { QuickStartCard, PresentationCard, GestureCard, DevicesCard } from "./components/RightPanel";
import { Footer } from "./components/Footer";
import { t, type Lang } from "./i18n";

function formatTime(s: number) {
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  return [h, m, sec].map((v) => String(v).padStart(2, "0")).join(":");
}

export default function App() {
  const [lang, setLang]                       = useState<Lang>("zh-CN");
  const s                                      = t[lang];

  const [isRecording, setIsRecording]         = useState(false);
  const [cameraActive]                        = useState(true);
  const [gesturesEnabled, setGesturesEnabled] = useState(true);
  const [gestureActive]                       = useState(true);
  const [targetApp, setTargetApp]             = useState("keynote");
  const [recordingMode, setRecordingMode]     = useState("camera-screen");
  const [layout, setLayout]                   = useState("pip");
  const [elapsedSec, setElapsedSec]           = useState(0);
  const [c1, setC1] = useState(false);
  const [c2, setC2] = useState(false);
  const [c3, setC3] = useState(false);
  const [c4, setC4] = useState(false);

  useEffect(() => {
    if (!isRecording) return;
    const id = setInterval(() => setElapsedSec((v) => v + 1), 1000);
    return () => clearInterval(id);
  }, [isRecording]);

  const appLabel: Record<string, string> = {
    powerpoint: s.appPPT, wps: s.appWPS, keynote: s.appKeynote, pdf: s.appPDF, html: s.appHTML,
  };

  return (
    <div style={{
      width: "100%", minWidth: 960, height: "100vh",
      background: "#0D0A07", display: "flex", flexDirection: "column",
      fontFamily: "var(--font-sans)", color: "#EDE8DC", overflow: "hidden",
    }}>

      {isRecording && (
        <div style={{ position: "fixed", top: 0, left: 0, right: 0, height: 2, zIndex: 200, background: "rgba(40,20,5,0.5)" }}>
          <div style={{ height: "100%", background: "#C84038", animation: "recProgress 60s linear infinite" }} />
        </div>
      )}

      <TopBar
        isRecording={isRecording}
        cameraActive={cameraActive}
        gestureActive={gestureActive && gesturesEnabled}
        targetApp={appLabel[targetApp] ?? targetApp}
        onToggleRecord={() => { setIsRecording((v) => { if (!v) setElapsedSec(0); return !v; }); }}
        onRehearseClick={() => {}}
        lang={lang} setLang={setLang} s={s}
      />

      <div style={{ flex: 1, minHeight: 0, display: "flex", gap: 14, padding: 16, overflow: "hidden" }}>

        {/* 左列：预览自适应宽度 */}
        <div style={{ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: 10 }}>
          <PreviewPanel
            cameraActive={cameraActive}
            isRecording={isRecording}
            gestureActive={gestureActive && gesturesEnabled}
            elapsedTime={formatTime(elapsedSec)}
            s={s}
          />
        </div>

        {/* 右列：固定 300px */}
        <div style={{ flexShrink: 0, width: 300, display: "flex", flexDirection: "column", gap: 8, overflowY: "auto", overflowX: "hidden", scrollbarWidth: "none" }}>
          <QuickStartCard
            collapsed={c1} onToggle={() => setC1(!c1)}
            isRecording={isRecording} cameraActive={cameraActive}
            gestureActive={gestureActive && gesturesEnabled}
            onRefreshDevices={() => {}} onTestSlide={() => {}} s={s}
          />
          <PresentationCard
            collapsed={c2} onToggle={() => setC2(!c2)}
            targetApp={targetApp} setTargetApp={setTargetApp}
            recordingMode={recordingMode} setRecordingMode={setRecordingMode}
            layout={layout} setLayout={setLayout}
            onOpenTestDeck={() => {}} s={s}
          />
          <GestureCard
            collapsed={c3} onToggle={() => setC3(!c3)}
            gesturesEnabled={gesturesEnabled} setGesturesEnabled={setGesturesEnabled}
            gestureActive={gestureActive && gesturesEnabled} s={s}
          />
          <DevicesCard collapsed={c4} onToggle={() => setC4(!c4)} onRescan={() => {}} s={s} />
        </div>
      </div>

      <Footer s={s} />

      <style>{`
        @keyframes recProgress{0%{width:0%}100%{width:100%}}
        ::-webkit-scrollbar{display:none}
        *{scrollbar-width:none}
        select option{background:#181309;color:#EDE8DC}
        button:focus-visible{outline:2px solid #C8923A;outline-offset:2px}
        button:focus:not(:focus-visible){outline:none}
      `}</style>
    </div>
  );
}
