/* Native integration runs only inside the packaged, trusted application. */
(() => {
  if (!window.MemoryAndroid) return;
  const nativeFetch = window.fetch.bind(window);
  const pending = new Map();
  let seq = 0;
  window.memoryNetworkResult = (id, result) => {
    const p = pending.get(id); if (!p) return;
    pending.delete(id); clearTimeout(p.timer);
    if (result.error) p.reject(new Error(result.error));
    else p.resolve(new Response(Uint8Array.from(atob(result.body), c => c.charCodeAt(0)), {status: result.status}));
  };
  window.fetch = (input, options = {}) => {
    const url = String(input);
    if (!url.startsWith('https://chat.deepseek.com/')) return nativeFetch(input, options);
    return new Promise((resolve, reject) => {
      const id = String(++seq);
      const timer = setTimeout(() => {pending.delete(id); reject(new Error('انتهت مهلة الاتصال. حاول مجدداً.'));}, 150000);
      pending.set(id, {resolve, reject, timer});
      MemoryAndroid.request(id, url, JSON.stringify({headers: options.headers || {}, body: options.body || '{}'}));
    });
  };
  let currentRecognition;
  class NativeRecognition {
    start() { currentRecognition = this; MemoryAndroid.startVoice(this.lang || 'ar'); }
    stop() { MemoryAndroid.stopVoice(); }
    abort() { this.stop(); }
  }
  window.SpeechRecognition = NativeRecognition;
  window.memoryVoiceEvent = (type, value) => {
    const r = currentRecognition; if (!r) return;
    if (type === 'result' || type === 'partial') {
      const result = [{transcript: value}]; result.isFinal = type === 'result';
      r.onresult?.({results: [result], resultIndex: 0});
    } else if (type === 'error') r.onerror?.({error: value});
    else if (type === 'start') r.onstart?.();
    else if (type === 'end') r.onend?.();
  };
  window.memoryChat = async (token, messages) => {
    const {callDeepSeekWeb} = await import('./lib/deepseek-web-client.js');
    const result = await callDeepSeekWeb({dsToken: token, messages, model: 'deepseek-chat'});
    return String(result?.choices?.[0]?.message?.content || '');
  };
})();
