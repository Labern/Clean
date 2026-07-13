(() => {
  const READY = "conversation-calendar:extension-ready";
  let activePort = null;

  const announce = () => window.dispatchEvent(new CustomEvent(READY));
  announce();
  window.addEventListener("conversation-calendar:page-ready", announce);

  window.addEventListener("conversation-calendar:sync-request", () => {
    if (activePort) activePort.disconnect();
    activePort = chrome.runtime.connect({ name: "conversation-calendar-live" });
    activePort.onMessage.addListener((message) => {
      window.dispatchEvent(new CustomEvent("conversation-calendar:sync-event", { detail: message }));
    });
    activePort.onDisconnect.addListener(() => { activePort = null; });
    activePort.postMessage({ type: "sync" });
  });
})();
