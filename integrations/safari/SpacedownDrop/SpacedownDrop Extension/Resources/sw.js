// Service worker: clicking the toolbar icon opens the dropzone as a full tab.
// A full tab (not a popup) is required because popups close when focus leaves
// the browser, which would abort a drag coming from Finder.
chrome.action.onClicked.addListener(() => {
  chrome.tabs.create({ url: chrome.runtime.getURL("dropzone.html") });
});
