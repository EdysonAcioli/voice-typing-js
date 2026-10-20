// Digitação por Voz — 100% offline, streaming em tempo real
// sherpa-onnx WASM + Zipformer streaming pt (transdutor) — mesma arquitetura
// do "Digitação por Voz" do Windows: parciais incrementais + detecção de endpoint.
//
// Latência otimizada:
//  - Engine em Web Worker dedicado (arquitetura do SDK oficial Kroko):
//    o decode (~250ms/chunk) roda fora da main thread — nunca compete
//    com a UI nem com a captura do AudioWorklet
//  - AudioWorklet (~8ms de buffer) em vez de ScriptProcessor (256ms)
//  - Warm-up do engine após carregar (elimina custo frio do 1º decode)

const btn = document.getElementById("mic-btn");
const statusEl = document.getElementById("status");
const transcriptEl = document.getElementById("transcript");
const interimEl = document.getElementById("interim");
const micWrap = document.getElementById("mic-wrap");
const levelRing = document.getElementById("level-ring");
const statsEl = document.getElementById("stats");

function setStatus(text, cls) {
  statusEl.textContent = text;
  statusEl.className = cls || "";
}

// ─── Engine em Web Worker ───
let engineReady = false;
const t0 = performance.now();

const worker = new Worker("engine-worker.js");
const pending = new Map();
let taskCounter = 0;

worker.onmessage = (event) => {
  const { id, dir, data, error } = event.data ?? {};
  if (id === undefined || dir !== "sender") return;
  if (id === "init") {
    if (error) {
      setStatus("Erro ao inicializar reconhecedor: " + error, "error");
    } else {
      engineReady = true;
      const secs = ((performance.now() - t0) / 1000).toFixed(1);
      setStatus(`Modelo carregado em ${secs}s — pronto (Ctrl+Espaço)`);
      btn.disabled = false;
    }
    return;
  }
  const task = pending.get(id);
  if (!task) return;
  pending.delete(id);
  error ? task.reject(new Error(error)) : task.resolve(data);
};

function postTask(type, payload, transfer) {
  return new Promise((resolve, reject) => {
    taskCounter++;
    pending.set(taskCounter, { resolve, reject });
    worker.postMessage({ id: taskCounter, type, dir: "receiver", payload }, transfer);
  });
}

// ─── Captura de microfone: AudioWorklet 16 kHz mono Float32 ───
let audioCtx = null;
let mediaStream = null;
let sourceNode = null;
let workletNode = null;
let listening = false;

const TARGET_SR = 16000;

async function startListening() {
  if (!engineReady) return;

  mediaStream = await navigator.mediaDevices.getUserMedia({
    audio: {
      channelCount: 1,
      echoCancellation: true,
      noiseSuppression: true,
    },
  });

  audioCtx = new AudioContext({
    sampleRate: TARGET_SR,
    latencyHint: "interactive", // menor latência de captura
  });
  await audioCtx.resume();
  sourceNode = audioCtx.createMediaStreamSource(mediaStream);

  await audioCtx.audioWorklet.addModule("voice-capture-worklet.js");
  workletNode = new AudioWorkletNode(audioCtx, "voice-capture", {
    numberOfInputs: 1,
    numberOfOutputs: 1,
    channelCount: 1,
    outputChannelCount: [1],
  });
  workletNode.port.onmessage = (ev) => {
    if (!listening) return;
    onAudioChunk(ev.data.samples, ev.data.level);
  };
  sourceNode.connect(workletNode);
  // saída conectada ao destination apenas para o worklet rodar;
  // sem feedback: o processador não copia a entrada para a saída
  workletNode.connect(audioCtx.destination);

  await postTask("createStream");
  listening = true;
  chunkCount = 0;
  listenStart = performance.now();
  micWrap.classList.add("listening");
  btn.classList.add("on");
  btn.title = "Parar (Ctrl+Espaço)";
  setStatus("Ouvindo... fale livremente", "listening");
}

// ─── Loop streaming: feed → decode no worker → parcial → endpoint ───
let committedText = "";
let lastPartial = "";
let chunkCount = 0;
let listenStart = 0;

function updateStats() {
  const words = (committedText.trim() ? committedText.trim().split(/\s+/).length : 0);
  const secs = listening ? ((performance.now() - listenStart) / 1000).toFixed(0) : 0;
  statsEl.textContent = listening
    ? `${words} palavra${words === 1 ? "" : "s"} • ${secs}s`
    : words
      ? `${words} palavra${words === 1 ? "" : "s"}`
      : "";
}

function onAudioChunk(samples, level) {
  if (!listening) return;
  chunkCount++;

  // medidor de nível de voz (0–100%)
  if (level !== undefined) {
    const pct = Math.min(100, Math.round((level / 0.25) * 100));
    levelRing.style.setProperty("--lvl", pct);
  }

  // stats a cada ~0.5s (64 chunks de 8ms)
  if (chunkCount % 64 === 0) updateStats();

  // transfere o buffer sem cópia (zero-copy) para o worker
  postTask("acceptWaveform", { sampleRate: TARGET_SR, samples }, [samples.buffer])
    .then((res) => {
      if (!res) return;
      const { text, isEndpoint } = res;

      if (text && text !== lastPartial) {
        lastPartial = text;
        interimEl.textContent = text;
      }

      if (isEndpoint && lastPartial) {
        committedText +=
          (committedText && !committedText.endsWith(" ") ? " " : "") + lastPartial;
        transcriptEl.value = committedText;
        transcriptEl.scrollTop = transcriptEl.scrollHeight;
        lastPartial = "";
        interimEl.textContent = "";
      }
    })
    .catch(() => {});
}

function stopListening() {
  listening = false;
  btn.classList.remove("on");
  micWrap.classList.remove("listening");
  levelRing.style.setProperty("--lvl", 0);
  btn.title = "Iniciar (Ctrl+Espaço)";
  updateStats();

  // commit final do que ficou pendente
  postTask("flush")
    .then((res) => {
      const text = res?.text ?? "";
      const pendingText = lastPartial && text !== lastPartial ? text : lastPartial;
      if (pendingText) {
        committedText +=
          (committedText && !committedText.endsWith(" ") ? " " : "") + pendingText;
        transcriptEl.value = committedText;
      }
      lastPartial = "";
      interimEl.textContent = "";
    })
    .catch(() => {})
    .finally(() => postTask("freeStream").catch(() => {}));

  try {
    if (workletNode) workletNode.disconnect();
    if (sourceNode) sourceNode.disconnect();
    if (audioCtx) audioCtx.close();
    if (mediaStream) mediaStream.getTracks().forEach((t) => t.stop());
  } catch (e) {
    /* ignora */
  }
  workletNode = null;
  sourceNode = null;
  audioCtx = null;
  mediaStream = null;

  setStatus("Parado");
}

btn.addEventListener("click", () => {
  if (listening) stopListening();
  else startListening();
});

// atalho: Ctrl+Espaço alterna escuta (nosso "Win+H")
document.addEventListener("keydown", (ev) => {
  if (ev.ctrlKey && ev.code === "Space") {
    ev.preventDefault();
    if (!btn.disabled) btn.click();
  }
});

// ─── Ações do editor ───
document.getElementById("copy-btn").addEventListener("click", async (ev) => {
  const text = transcriptEl.value;
  if (!text) return;
  try {
    await navigator.clipboard.writeText(text);
    const b = ev.currentTarget;
    const orig = b.textContent;
    b.textContent = "✓ Copiado";
    setTimeout(() => (b.textContent = orig), 1200);
  } catch (e) {
    transcriptEl.select();
    document.execCommand("copy");
  }
});

document.getElementById("clear-btn").addEventListener("click", () => {
  transcriptEl.value = "";
  committedText = "";
  lastPartial = "";
  interimEl.textContent = "";
  updateStats();
});
