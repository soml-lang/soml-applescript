(*
Regression tests for independently reproduced bugs.
*)
use AppleScript version "2.8"
use framework "Foundation"
use scripting additions
use soml : script "SOML"

property failures : {}
property testCount : 0

on run
	set failures to {}
	set testCount to 0
	testLoneSurrogateEncoding()
	if failures is not {} then
		error soml's joinTexts(failures, linefeed)
	end if
	return (testCount as text) & " bug regression checks passed"
end run

on check(theName, actual, expected)
	set testCount to testCount + 1
	considering case, diacriticals, hyphens, punctuation and white space
		if actual is not expected then
			set end of failures to theName
		end if
	end considering
end check

on testLoneSurrogateEncoding()
	set emojiString to current application's NSString's stringWithString:(character id 128512)
	set highSurrogate to (emojiString's substringToIndex:1) as text
	set lowSurrogate to (emojiString's substringFromIndex:1) as text
	-- AppleScript's `id of` incorrectly combines a high surrogate with an ordinary following character.
	repeat with surrogate in {highSurrogate, lowSurrogate}
		repeat with suffix in {"", "a", "'", tab, character id 769, character id 128512}
			set malformedText to "prefix" & contents of surrogate & contents of suffix
			repeat with isKey in {false, true}
				if isKey then
					set theValue to {class:SOML object, entries:{{malformedText, 1}}}
				else
					set theValue to {malformedText}
				end if
				repeat with canonical in {false, true}
					try
						if canonical then
							soml's encodeCanonical(theValue)
						else
							soml's encode(theValue)
						end if
						check("malformed Unicode must fail", true, false)
					on error message number errorNumber
						check("malformed Unicode error number", errorNumber, 2)
						check("malformed Unicode diagnostic", message contains "lone surrogate", true)
					end try
				end repeat
			end repeat
		end repeat
	end repeat
	-- Valid surrogate pairs must still round trip, including beside fragile Unicode prefixes.
	repeat with prefix in {"", character id 65279, character id 65534}
		set validText to contents of prefix & character id 128512 & "a'" & tab
		check("valid astral Unicode round trip", id of item 1 of soml's decode(soml's encode({validText})), id of validText)
	end repeat
end testLoneSurrogateEncoding
