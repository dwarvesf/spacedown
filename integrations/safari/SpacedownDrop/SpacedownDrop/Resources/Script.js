// Called once by ViewController: the Safari section shows only when the app bundles
// the Safari extension (a --with-safari build).
function setup(hasSafari) {
    document.querySelector("section.safari").hidden = !hasSafari;
}

// Safari extension state, reported by ViewController for a --with-safari build.
function show(enabled, useSettingsInsteadOfPreferences) {
    if (useSettingsInsteadOfPreferences) {
        document.getElementsByClassName('state-off')[0].innerText = "The Safari extension is off. Turn it on in the Extensions section of Safari Settings.";
        document.getElementsByClassName('state-unknown')[0].innerText = "Turn on the Safari extension in the Extensions section of Safari Settings.";
    }

    if (typeof enabled === "boolean") {
        document.body.classList.toggle(`state-on`, enabled);
        document.body.classList.toggle(`state-off`, !enabled);
    } else {
        document.body.classList.remove(`state-on`);
        document.body.classList.remove(`state-off`);
    }
}

document.querySelector("button.open-extensions").addEventListener("click", function () {
    webkit.messageHandlers.controller.postMessage("open-extensions");
});
document.querySelector("button.open-preferences").addEventListener("click", function () {
    webkit.messageHandlers.controller.postMessage("open-preferences");
});
