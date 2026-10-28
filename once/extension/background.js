// Keyboard shortcuts → the page. Everything else lives in content.js.
const ext = globalThis.browser || globalThis.chrome;
ext.commands.onCommand.addListener(async (cmd) => {
  const [tab] = await ext.tabs.query({ active: true, currentWindow: true });
  if (tab) ext.tabs.sendMessage(tab.id, cmd).catch(() => {});
});
