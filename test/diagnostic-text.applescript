(*
Abbreviating genuine malformed AppleScript text must preserve the documented helper error number instead of failing while reconstructing a Unicode scalar. Instant diagnostics are also compared with the JavaScript reference message for message, which pins their text and position.
*)
use AppleScript version "2.8"
use framework "Foundation"
use scripting additions
use soml : script "SOML"
property failures : {}
property testCount : 0

set nativeAstral to current application's NSString's stringWithString:(character id 1114111)
set highSurrogate to (nativeAstral's substringToIndex:1) as text
set suffix to ""
repeat 50 times
	set suffix to suffix & "a"
end repeat
repeat with afterSurrogate in {"a", character id 65534, character id 65535}
	set malformedText to "bad" & highSurrogate & contents of afterSurrogate & suffix
	set nativeText to current application's NSString's stringWithString:malformedText
	if (nativeText's dataUsingEncoding:(current application's NSUTF8StringEncoding)) is not missing value then
		error "Fixture lost its lone surrogate before reaching the library"
	end if
	set testCount to testCount + 1
	try
		soml's toNumber({class:SOML int, value:malformedText})
		set end of failures to "Accepted malformed integer text"
	on error message number errorNumber
		if errorNumber is not -1703 then
			set end of failures to "Malformed tagged integer: expected -1703, got " & errorNumber
		end if
	end try
	set testCount to testCount + 1
	try
		soml's decode("x: " & malformedText)
		set end of failures to "Accepted malformed document text"
	on error message number errorNumber from details
		if errorNumber is not 1 or |line| of details is not 1 or |column| of details is not 7 then
			set end of failures to "Malformed source: changed error number or scalar position"
		end if
	end try
end repeat

-- The whole message is compared, so a divergence in the text or in the position fails. The tokens of 1000 and 1001 characters pin the diagnosed length at the reference's cutoff.
set longDigits to "1"
repeat 10 times
	set longDigits to longDigits & longDigits
end repeat
set tabSeparated to "a: 2026-09-19" & tab & "14:00:00"
set separator to "The date and time separator in an instant is an uppercase “T”, not a space"
set instantFormat to "An instant is written as 2026-09-19T14:00:00Z, with an optional fraction of up to nine digits and an offset of Z or ±HH:MM"
-- An offset on its own after a space, as in 2026-09-19T14:00:00 Z, still gets the long local-time message: the reference's short offset diagnostic needs a source scan that osacompile's identifier table (internal table overflow, -2707) has no room for in this file.
set offsetHint to "An instant needs an offset: Z or ±HH:MM. A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19T14:00:00', or add the offset it was meant in"
set spaceHint to ". A date and time without an offset is a local time, which is not an instant, so write it as a string, as in '2026-09-19 14:00:00'"
set fractionPreview to "2026-09-19T14:00:00." & text 1 thru 20 of longDigits & "…"
set instantCases to {{sourceText:"a: 2026-09-19  14:00:00", messageText:separator & ", and an instant needs the offset it was meant in, as in 2026-09-19T14:00:00Z for UTC" & spaceHint & " at line 1, column 4"}, {sourceText:tabSeparated, messageText:separator & ", and an instant needs the offset it was meant in, as in 2026-09-19T14:00:00Z for UTC" & spaceHint & " at line 1, column 4"}, {sourceText:"a: 2026-09-19 1:00", messageText:separator & ". " & instantFormat & " at line 1, column 4"}, {sourceText:"a: 2026-09-19 1:00:00", messageText:separator & ". " & instantFormat & " at line 1, column 4"}, {sourceText:"a: 2026-01-01T00:00:00[Europe/Oslo]", messageText:"An instant needs an offset: Z or ±HH:MM at line 1, column 4"}, {sourceText:"a: [2026-09-19T14:00:00[]", messageText:"An instant needs an offset: Z or ±HH:MM at line 1, column 5"}, {sourceText:"a: 2026-09-19T14:00:00,5x", messageText:"An instant needs an offset: Z or ±HH:MM at line 1, column 4"}, {sourceText:"a: 2026-09-19T14:00:00/2026-09-20T15:00:00", messageText:"An instant needs an offset: Z or ±HH:MM at line 1, column 4"}, {sourceText:"a: 2026-09-19T14:00:00 5{", messageText:"An instant needs an offset: Z or ±HH:MM at line 1, column 4"}, {sourceText:"a: 2026-09-19T14:00:00 +02:00:00", messageText:offsetHint & " at line 1, column 4"}, {sourceText:"a: 2026-09-19T14:00:00." & text 1 thru 979 of longDigits & "Z", messageText:"Invalid instant " & fractionPreview & ": a fractional second has at most nine digits at line 1, column 4"}, {sourceText:"a: 2026-09-19T14:00:00." & text 1 thru 980 of longDigits & "Z", messageText:"Invalid instant “" & fractionPreview & "”. " & instantFormat & " at line 1, column 4"}, {sourceText:"a: 2026-09-19t14:00:00." & text 1 thru 980 of longDigits & "Z", messageText:"Invalid instant “2026-09-19t14:00:00." & text 1 thru 20 of longDigits & "…”. " & instantFormat & " at line 1, column 4"}, {sourceText:"a: 2026-09-19T14:00:00." & text 1 thru 980 of longDigits & "z", messageText:"Invalid instant “" & fractionPreview & "”. " & instantFormat & " at line 1, column 4"}, {sourceText:"a: 2026-09-19 14:00:00." & text 1 thru 981 of longDigits, messageText:separator & ". " & instantFormat & " at line 1, column 4"}}
repeat with instantCase in instantCases
	set testCount to testCount + 1
	try
		soml's decode(sourceText of instantCase)
		set end of failures to "Accepted invalid instant text: " & sourceText of instantCase
	on error message number errorNumber from details
		if errorNumber is not 1 or message is not messageText of instantCase then
			set end of failures to "Wrong instant diagnostic for “" & sourceText of instantCase & "”: " & message
		end if
	end try
end repeat

if failures is not {} then
	error soml's joinTexts(failures, linefeed)
end if
return (testCount as text) & " diagnostic text checks passed"
