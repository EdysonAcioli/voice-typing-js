// AudioWorklet: captura com latência mínima (~8ms) e zero perda de áudio.
// Roda em thread própria de áudio — o decode WASM no main thread nunca
// bloqueia a captura (diferente do ScriptProcessor).
class VoiceCaptureProcessor extends AudioWorkletProcessor {
  process(inputs) {
    const input = inputs[0];
    if (input && input[0] && input[0].length) {
      // copia: o buffer do worklet é reutilizado pelo sistema de áudio
      this.port.postMessage(input[0].slice(0));
    }
    return true;
  }
}

registerProcessor("voice-capture", VoiceCaptureProcessor);
