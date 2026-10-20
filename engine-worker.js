// Engine worker: roda o sherpa-onnx WASM fora da main thread.
// Mesma arquitetura do SDK oficial da Kroko (fornecedor do modelo pt):
// o decode pesado (~250ms/chunk) nunca compete com a UI nem com a
// captura de áudio do AudioWorklet.

// Configurar Module ANTES do importScripts: o loader faz
// var Module = typeof Module != "undefined" ? Module : {} — reusa este
// objeto. O .data é buscado no importScripts (IIFE), então locateFile
// precisa já existir; senão o fetch iria para a raiz (404).
var Module = {
  locateFile: (path) => "sherpa-wasm/" + path,
};

importScripts("sherpa-wasm/sherpa-onnx-asr.js", "sherpa-wasm/sherpa-onnx-wasm-main-asr.js");

let recognizer = null;
let stream = null;

function reply(id, data) {
  self.postMessage({ id, dir: "sender", data });
}
function replyError(id, error) {
  self.postMessage({ id, dir: "sender", error: error?.message ?? String(error) });
}

Module.onRuntimeInitialized = async () => {
  try {
    recognizer = createOnlineRecognizer(Module, {
      featConfig: { sampleRate: 16000, featureDim: 80 },
      modelConfig: {
        transducer: {
          encoder: "./encoder.onnx",
          decoder: "./decoder.onnx",
          joiner: "./joiner.onnx",
        },
        tokens: "./tokens.txt",
        numThreads: 1,
        provider: "cpu",
        debug: 0,
        modelType: "",
        modelingUnit: "cjkchar",
        bpeVocab: "",
      },
      decodingMethod: "greedy_search",
      maxActivePaths: 4,
      enableEndpoint: 1,
      rule1MinTrailingSilence: 1.2,
      rule2MinTrailingSilence: 0.6,
      rule3MinUtteranceLength: 20,
      hotwordsFile: "",
      hotwordsScore: 1.5,
      ctcFstDecoderConfig: { graph: "", maxActive: 3000 },
      ruleFsts: "",
      ruleFars: "",
    });

    // Warm-up: aquece ONNX Runtime + JIT do WASM com silêncio.
    // 3s de silêncio → 2 decodes (o 1º chunk fica pronto com ~1430ms).
    const ws = recognizer.createStream();
    ws.acceptWaveform(16000, new Float32Array(48000));
    while (recognizer.isReady(ws)) recognizer.decode(ws);
    recognizer.getResult(ws);
    ws.free();

    reply("init", { ok: true });
  } catch (e) {
    replyError("init", e);
  }
};

const handlers = {
  createStream: () => {
    stream = recognizer.createStream();
    return { ok: true };
  },

  acceptWaveform: (payload) => {
    if (!stream) return;
    stream.acceptWaveform(payload.sampleRate, payload.samples);
    // decoda tudo que estiver pronto, de forma incremental
    let decoded = 0;
    while (recognizer.isReady(stream)) {
      recognizer.decode(stream);
      decoded++;
    }
    if (decoded === 0) return null;

    const isEndpoint = recognizer.isEndpoint(stream);
    const result = recognizer.getResult(stream).text;
    if (isEndpoint && result) recognizer.reset(stream);
    return { text: result, isEndpoint };
  },

  flush: () => {
    // commit final ao parar: pega o que ficou pendente
    if (!stream) return null;
    let text = "";
    while (recognizer.isReady(stream)) recognizer.decode(stream);
    text = recognizer.getResult(stream).text;
    return { text, isEndpoint: false };
  },

  freeStream: () => {
    if (stream) {
      stream.free();
      stream = null;
    }
    return { ok: true };
  },
};

self.onmessage = async (event) => {
  const { id, type, dir, payload } = event.data ?? {};
  if (id === undefined || dir !== "receiver") return;
  try {
    const handler = handlers[type];
    const result = await handler?.(payload);
    reply(id, result);
  } catch (e) {
    replyError(id, e);
  }
};
