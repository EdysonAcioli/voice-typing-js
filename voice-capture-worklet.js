// AudioWorklet: captura com latência mínima (~8ms) e zero perda de áudio.
// Roda em thread própria de áudio — o decode WASM no main thread nunca
// bloqueia a captura (diferente do ScriptProcessor).
class VoiceCaptureProcessor extends AudioWorkletProcessor {
  process(inputs) {
    const input = inputs[0];
    if (input && input[0] && input[0].length) {
      const samples = input[0];
      // nível RMS do chunk para o medidor de voz
      let sum = 0;
      for (let i = 0; i < samples.length; i++) sum += samples[i] * samples[i];
      const level = Math.sqrt(sum / samples.length);
      // copia: o buffer do worklet é reutilizado pelo sistema de áudio
      this.port.postMessage({ samples: samples.slice(0), level });
    }
    return true;
  }
}

registerProcessor("voice-capture", VoiceCaptureProcessor);
