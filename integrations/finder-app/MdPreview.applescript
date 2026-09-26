-- MdPreview.app: a thin AppleScript "open handler" so that double-clicking a
-- .md in Finder (or "Open With > MdPreview", or dragging a .md onto the app
-- icon) renders it through the local md-preview CLI and opens the HTML.
--
-- macOS delivers opened files to an app via the Apple Event `odoc`, surfaced
-- here as `on open theItems`. `on run` covers launching the app with no file
-- (we prompt for one). Both delegate to the shared `md-open` wrapper, whose
-- absolute path is injected by install.sh at compile time (the __MD_OPEN__
-- token below), so this source stays machine-independent.

on open theItems
	repeat with f in theItems
		set p to POSIX path of f
		try
			do shell script "MD_PREVIEW_BROWSER=Safari __MD_OPEN__ " & quoted form of p
		on error errMsg number errNum
			display notification errMsg with title "md-preview failed" subtitle p
		end try
	end repeat
end open

on run
	set f to choose file with prompt "Pick a markdown file to preview:" of type {"net.daringfireball.markdown", "public.plain-text", "public.text"}
	set p to POSIX path of f
	try
		do shell script "MD_PREVIEW_BROWSER=Safari __MD_OPEN__ " & quoted form of p
	on error errMsg number errNum
		display notification errMsg with title "md-preview failed" subtitle p
	end try
end run
