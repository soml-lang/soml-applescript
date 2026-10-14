(*
Long scalar tokens must retain exact range checks and diagnostics without keeping unbounded numeric scratch buffers.
*)
use AppleScript version "2.8"
use soml : script "SOML"

on run
	set zeros to "0"
	repeat 14 times
		set zeros to zeros & zeros
	end repeat
	set parsed to soml's decode("[1.5" & zeros & "s, 0." & zeros & "s, 0.0000000000025" & zeros & "h]")
	if value of item 1 of parsed is not "1.5s" or value of item 2 of parsed is not "0s" or value of item 3 of parsed is not "0.000000009s" then
		error "Long trailing-zero fractions changed duration precision" number 99
	end if
	checkInvalid("[0." & zeros & "1s]", "it is not a whole number of nanoseconds")
	checkInvalid("[0.0000000000025" & zeros & "h1s]", "only the last part may have a fraction")
	checkInvalid("[1" & zeros & "ns]", "outside the 64-bit range")
	checkInvalid("[1" & zeros & "s]", "outside the 64-bit range")
	checkInvalid("[1" & zeros & "_s]", "an underscore must be between two digits")
	checkInvalid("[1.0" & zeros & "_s]", "an underscore must be between two digits")
	set letters to "strangeunit"
	repeat 10 times
		set letters to letters & letters
	end repeat
	checkInvalid("[1" & letters & "]", "“strangeuni…” is not a unit")
	set yearLetters to "years"
	repeat 11 times
		set yearLetters to yearLetters & yearLetters
	end repeat
	checkInvalid("[1" & yearLetters & "]", "A string value must be quoted")
	checkInvalid("[1years]", "there is no year unit")
	checkInvalid("[1YEARS]", "there is no year unit")
	-- Long codepoint previews retain the complete public diagnostics in each scalar parser.
	set numericPreview to "1" & text 1 thru 39 of zeros & "…"
	checkInvalidMessage("[1" & zeros & "]", "The integer " & numericPreview & " is outside the 64-bit range (-9223372036854775808 to 9223372036854775807) at line 1, column 2")
	checkInvalidMessage("[1" & zeros & "ns]", "Invalid duration " & numericPreview & ": it is outside the 64-bit range of nanoseconds, about 292 years either way at line 1, column 2")
	checkInvalidMessage("[2026-09-19T12:34:56." & zeros & "Z]", "Invalid instant “2026-09-19T12:34:56." & text 1 thru 20 of zeros & "…”. An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM at line 1, column 2")
	set astralText to ""
	repeat 19 times
		set astralText to astralText & character id 129412
	end repeat
	try
		soml's toSeconds({class:SOML duration, value:"1" & astralText & character id 129412})
		error "Accepted invalid duration with astral characters" number 99
	on error message number errorNumber
		if errorNumber is not -1703 or id of message is not id of ("toSeconds() got an invalid value: Invalid duration 1" & astralText & "…: every number needs a unit: h, m, s, ms, us, or ns") then
			error "Codepoint preview split an astral scalar: " & message number 99
		end if
	end try
	-- Decimal and each alternate radix must reject oversized integers before converting their digits.
	repeat with prefix in {"1", "0xF", "0o7", "0b1"}
		checkInvalid("[" & prefix & zeros & "]", "outside the 64-bit range")
	end repeat
	return "19 reader scalar limit checks passed"
end run

on checkInvalid(sourceText, expectedReason)
	try
		soml's decode(sourceText)
		error "Accepted an invalid long scalar token" number 99
	on error message number errorNumber
		if errorNumber is not 1 then
			error message number errorNumber
		end if
		if message does not contain expectedReason then
			error "Wrong long-token diagnostic: " & message number 99
		end if
	end try
end checkInvalid

on checkInvalidMessage(sourceText, expectedMessage)
	try
		soml's decode(sourceText)
		error "Accepted invalid scalar with a bounded diagnostic" number 99
	on error message number errorNumber
		if errorNumber is not 1 or id of message is not id of expectedMessage then
			error "Wrong bounded scalar diagnostic: " & message number 99
		end if
	end try
end checkInvalidMessage
