(*
Valid long keys must remain readable and writable, including the boundary where AppleScript corrupts a native record's display.
*)
use AppleScript version "2.8"
use scripting additions
use soml : script "SOML"
property failures : {}
property testCount : 0

on checkObject(theName, theObject, expectedKey, expectedKeyText)
	set testCount to testCount + 1
	try
		set pairs to soml's entries(theObject)
		if (count pairs) is not 1 or id of item 1 of item 1 of pairs is not id of expectedKey or item 2 of item 1 of pairs is not 7 then
			set end of failures to theName & ": changed entries"
		end if
		set expectedText to expectedKeyText & ": 7" & linefeed
		if id of soml's encode(theObject) is not id of expectedText then
			set end of failures to theName & ": changed normal output"
		end if
		if id of soml's encodeCanonical(theObject) is not id of expectedText then
			set end of failures to theName & ": changed canonical output"
		end if
	on error message number errorNumber
		set end of failures to theName & ": " & errorNumber & " " & message
	end try
end checkObject

on testKey(theName, theKey, expectedKeyText)
	-- The object also needs to survive a surrounding list and a second construction call.
	repeat with methodName in {"decode", "construct", "nested decode", "nested construction"}
		try
			if contents of methodName is "decode" then
				set theObject to soml's decode(expectedKeyText & ": 7")
			else if contents of methodName is "construct" then
				set theObject to soml's fromEntries({{theKey, 7}})
			else if contents of methodName is "nested decode" then
				set theObject to item 1 of soml's decode("[{" & expectedKeyText & ": 7}]")
			else
				set theObject to soml's fromEntries({{"outer", soml's fromEntries({{theKey, 7}})}})
				set theObject to item 2 of item 1 of soml's entries(theObject)
			end if
			checkObject(theName & " " & methodName, theObject, theKey, expectedKeyText)
		on error message number errorNumber
			set testCount to testCount + 1
			set end of failures to theName & " " & methodName & ": " & errorNumber & " " & message
		end try
	end repeat
end testKey

on testValues(theKey)
	-- Nonzero values exercise the actual record independently of its zero-valued label probe.
	set instantText to "2026-09-19T12:34:56Z"
	set nativeDate to soml's toDate({class:«class SOMt», value:instantText})
	repeat with valueKind in {"real", "date", "record"}
		if contents of valueKind is "real" then
			set expectedValue to 0.125
			set valueText to "0.125"
			set canonicalValueText to valueText
		else if contents of valueKind is "date" then
			set expectedValue to nativeDate
			set valueText to instantText
			set canonicalValueText to valueText
		else
			set expectedValue to {zeta:2.5, alpha:true}
			set valueText to "{" & linefeed & tab & "zeta: 2.5" & linefeed & tab & "alpha: true" & linefeed & "}"
			set canonicalValueText to "{" & linefeed & tab & "alpha: true" & linefeed & tab & "zeta: 2.5" & linefeed & "}"
		end if
		set expectedText to "zeta: 99" & linefeed & theKey & ": " & valueText & linefeed & "alpha: 1" & linefeed
		set expectedCanonicalText to "alpha: 1" & linefeed & theKey & ": " & canonicalValueText & linefeed & "zeta: 99" & linefeed
		repeat with methodName in {"decode", "construct"}
			set theName to "value " & valueKind & " " & methodName & " at " & (length of theKey)
			set testCount to testCount + 1
			try
				if contents of methodName is "decode" then
					set theObject to soml's decode(expectedText)
				else
					set theObject to soml's fromEntries({{"zeta", 99}, {theKey, expectedValue}, {"alpha", 1}})
				end if
				set pairs to soml's entries(theObject)
				if (count pairs) is not 3 or id of item 1 of item 1 of pairs is not id of "zeta" or id of item 1 of item 2 of pairs is not id of theKey or id of item 1 of item 3 of pairs is not id of "alpha" or item 2 of item 1 of pairs is not 99 or item 2 of item 3 of pairs is not 1 then
					set end of failures to theName & ": changed key order or value associations"
				end if
				set actualValue to item 2 of item 2 of pairs
				if contents of valueKind is "record" then
					set nestedPairs to soml's entries(actualValue)
					if (count nestedPairs) is not 2 or id of item 1 of item 1 of nestedPairs is not id of "zeta" or id of item 1 of item 2 of nestedPairs is not id of "alpha" or class of item 2 of item 1 of nestedPairs is not real or item 2 of item 1 of nestedPairs is not 2.5 or item 2 of item 2 of nestedPairs is not true then
						set end of failures to theName & ": changed nested values"
					end if
				else if contents of valueKind is "date" and contents of methodName is "decode" then
					if class of actualValue is not «class SOMt» or id of value of actualValue is not id of instantText then
						set end of failures to theName & ": changed instant"
					end if
				else if class of actualValue is not class of expectedValue or actualValue is not expectedValue then
					set end of failures to theName & ": changed scalar class or value"
				end if
				if id of soml's encode(theObject) is not id of expectedText then
					set end of failures to theName & ": changed normal output"
				end if
				if id of soml's encodeCanonical(theObject) is not id of expectedCanonicalText then
					set end of failures to theName & ": changed canonical key order or output"
				end if
			on error message number errorNumber
				set end of failures to theName & ": " & errorNumber & " " & message
			end try
		end repeat
	end repeat
end testValues

on run
	set failures to {}
	set testCount to 0
	repeat with fragment in {"a", "é", "🦄", "\\", "'", "|", "\""}
		repeat with keyLength in {1, 63, 64, 125, 126, 127, 128, 249, 250, 251, 252, 253, 254, 255, 256, 512}
			set theKey to ""
			repeat keyLength times
				set theKey to theKey & fragment
			end repeat
			set expectedKeyText to "'" & theKey & "'"
			if contents of fragment is "a" then
				set expectedKeyText to theKey
			else if contents of fragment is "'" then
				set expectedKeyText to "\"" & theKey & "\""
			end if
			testKey((fragment as text) & " repeated " & keyLength, theKey, expectedKeyText)
		end repeat
	end repeat
	repeat with keyLength in {249, 250, 251, 252, 253, 254, 255, 256}
		set theKey to ""
		repeat keyLength times
			set theKey to theKey & "b"
		end repeat
		set theKey to theKey & "-"
		testKey("barred ASCII label " & keyLength, theKey, theKey)
	end repeat
	repeat with keyLength in {249, 250, 251, 252, 253, 254, 255, 256}
		set theKey to "m"
		repeat (keyLength - 1) times
			set theKey to theKey & "d"
		end repeat
		testValues(theKey)
		-- Both SOML quotes and AppleScript's barred label escapes occur in one label.
		set escapedKey to theKey & "'\"|\\"
		set escapedKeyText to "\"" & theKey & "'\\\"|\\\\\""
		testKey("mixed quote and bar label " & keyLength, escapedKey, escapedKeyText)
	end repeat
	-- Readable native labels near the boundary should remain ordinary records.
	set theKey to ""
	repeat 251 times
		set theKey to theKey & "c"
	end repeat
	set testCount to testCount + 1
	if class of soml's fromEntries({{theKey, 7}}) is not record then
		set end of failures to "Readable 251-character label changed native construction"
	end if
	if failures is not {} then
		error soml's joinTexts(failures, linefeed)
	end if
	return (testCount as text) & " long key checks passed"
end run
