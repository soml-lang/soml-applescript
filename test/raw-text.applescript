(*
Raw Unicode data claims to be text without supporting text operations. Public APIs must reject it as an argument and preserve it when inspecting arbitrary entry values.
*)
use AppleScript version "2.8"
use framework "Foundation"
use scripting additions
use soml : script "SOML"
property failures : {}
property testCount : 0

on checkError(theName, theScript, expectedNumber)
	set testCount to testCount + 1
	try
		run theScript
		set end of failures to theName & " was accepted"
	on error message number errorNumber
		if errorNumber is not expectedNumber then
			set end of failures to theName & ": expected " & expectedNumber & ", got " & errorNumber
		end if
	end try
end checkError

on run
	set failures to {}
	set testCount to 0
	script decodeCase
		on run
			soml's decode(«data utxt0031»)
		end run
	end script
	checkError("decode raw data", decodeCase, -1703)
	script fileCase
		on run
			soml's decodeFile(«data utxt0031»)
		end run
	end script
	checkError("raw file path", fileCase, -1703)
	script entriesCase
		on run
			soml's fromEntries({{«data utxt0031», 1}})
		end run
	end script
	checkError("raw entry key", entriesCase, -1703)
	repeat with theTag in {{class:SOML int, value:«data utxt0031»}, {class:SOML instant, value:«data utxt0031»}, {class:SOML duration, value:«data utxt0031»}}
		script helperCase
			property tagged : contents of theTag
			on run
				if class of tagged is SOML int then
					soml's toNumber(tagged)
				else if class of tagged is SOML instant then
					soml's toDate(tagged)
				else
					soml's toSeconds(tagged)
				end if
			end run
		end script
		checkError("raw tagged helper value", helperCase, -1703)
		script encodingCase
			property tagged : contents of theTag
			on run
				soml's encode({a:tagged})
			end run
		end script
		checkError("raw tagged encoding value", encodingCase, 2)
	end repeat
	script encodingKeyCase
		on run
			soml's encode({class:SOML object, entries:{{«data utxt0031», 1}}})
		end run
	end script
	checkError("raw tagged object key", encodingKeyCase, 2)
	-- `fromEntries()` retains arbitrary values for inspection, even when they cannot be encoded.
	repeat with rawValue in {«data utxt0031», {«data utxt0031»}, {nested:«data utxt0031»}}
		set originalPairs to {{"raw-text-value", contents of rawValue}}
		set testCount to testCount + 1
		try
			set theObject to soml's fromEntries(originalPairs)
			if class of theObject is not SOML object or soml's entries(theObject) is not originalPairs then
				set end of failures to "Raw entry values changed"
			end if
		on error message number errorNumber
			set end of failures to "Raw entry values must be preserved: " & errorNumber
		end try
	end repeat
	if failures is not {} then
		error soml's joinTexts(failures, linefeed)
	end if
	return (testCount as text) & " raw text regression checks passed"
end run
