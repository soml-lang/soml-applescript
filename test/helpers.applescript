(*
Public helper regressions: large case-collision groups, Unicode ordering, safe errors, and state preservation after failures.

	make helpers
*)
use AppleScript version "2.8"
use framework "Foundation"
use scripting additions
use soml : script "SOML"

property testCount : 0

on run
	set testCount to 0
	testCaseVariants()
	testUnicodeOrder()
	testLongNumbers()
	testSafeErrors()
	testCallerState()
	check("negative exact integer", soml's toNumber({class:SOML int, value:"-9007199254740992"}), -9.007199254740992E+15)
	check("fractional duration", soml's toSeconds({class:SOML duration, value:"-1h30m0.000000001s"}), -5400.000000001)
	return (testCount as text) & " helper tests passed"
end run

on check(theName, actual, expected)
	set testCount to testCount + 1
	considering case, diacriticals, hyphens, punctuation and white space
		if actual is not expected then
			error theName & " failed"
		end if
	end considering
end check

on testCaseVariants()
	script Store
		property pairs : {}
	end script
	-- All 512 spellings fold to the same key, forcing the large-group duplicate path.
	repeat with variant from 0 to 511
		set theKey to ""
		set remaining to variant
		repeat 9 times
			if remaining mod 2 = 0 then
				set theKey to theKey & "a"
			else
				set theKey to theKey & "A"
			end if
			set remaining to remaining div 2
		end repeat
		set end of Store's pairs to {theKey, variant}
	end repeat
	set theObject to soml's fromEntries(Store's pairs)
	check("case variants need a tagged object", class of theObject, SOML object)
	check("case variants preserve spelling and order", soml's entries(theObject), Store's pairs)
	set encodedVariants to soml's encode(theObject)
	check("reader handles a large identical-folded-key group", soml's entries(soml's decode(encodedVariants)), Store's pairs)
	try
		soml's decode(encodedVariants & item 1 of item 400 of Store's pairs & ": -1")
		error "late exact duplicate in folded-key group was accepted" number 99
	on error message number errorNumber from details
		check("reader rejects late exact duplicate in folded-key group", errorNumber, 1)
		check("late case-variant duplicate position", {|line| of details, |column| of details}, {513, 1})
	end try
	set end of Store's pairs to {item 1 of item 400 of Store's pairs, -1}
	try
		soml's fromEntries(Store's pairs)
		error "duplicate case variant was accepted"
	on error message number errorNumber
		check("duplicate beyond the small-group threshold", errorNumber, 2)
	end try
	-- A large group with no case collisions must still materialize native records.
	set Store's pairs to {}
	repeat with theIndex from 1 to 257
		set end of Store's pairs to {"helper-key-" & theIndex, theIndex}
	end repeat
	set theObject to soml's fromEntries(Store's pairs)
	check("257 unique keys materialize", class of theObject, record)
	check("large native record retains order", soml's entries(theObject), Store's pairs)
end testCaseVariants

on testUnicodeOrder()
	set astralKey to character id 65536
	set highBMPKey to character id 57344
	set combinedKey to "e" & character id 769
	set composedKey to character id 233
	set pairs to {{astralKey, 4}, {composedKey, 2}, {highBMPKey, 3}, {combinedKey, 1}}
	set encoded to soml's encodeCanonical(soml's fromEntries(pairs))
	set expected to "'" & combinedKey & "': 1" & linefeed & "'" & composedKey & "': 2" & linefeed & "'" & highBMPKey & "': 3" & linefeed & "'" & astralKey & "': 4" & linefeed
	check("canonical keys follow scalar order without normalization", encoded, expected)
	check("noncanonical order is kept", soml's entries(soml's decode(soml's encode(soml's fromEntries(pairs)))), pairs)
end testUnicodeOrder

on testLongNumbers()
	set longDigits to "9"
	repeat 13 times
		set longDigits to longDigits & longDigits
	end repeat
	repeat with tokenText in {longDigits, "0x" & longDigits, "1e" & longDigits, "2026-01-01T00:00:00." & longDigits & "Z"}
		try
			soml's decode("[" & tokenText & "]")
			error "oversized number was accepted"
		on error message number errorNumber from details
			check("long number remains a document error", errorNumber, 1)
			check("long number error position", {|line| of details, |column| of details}, {1, 2})
		end try
	end repeat
end testLongNumbers

on testSafeErrors()
	set directionalKey to "x" & character id 1564
	try
		soml's fromEntries({{directionalKey, 1}, {directionalKey, 2}})
		error "duplicate directional key was accepted"
	on error message number errorNumber
		check("Arabic direction control error number", errorNumber, 2)
		check("Arabic direction control is escaped", message contains "\\u{61c}", true)
		check("Arabic direction control is absent", (id of message) contains 1564, false)
	end try
	set unsafeKey to "x" & character id 27 & character id 8238
	try
		soml's fromEntries({{unsafeKey, 1}, {unsafeKey, 2}})
		error "duplicate unsafe key was accepted"
	on error message number errorNumber
		check("duplicate helper error number", errorNumber, 2)
		check("duplicate helper diagnostic escapes bidi", message contains "\\u{202e}", true)
	end try
	try
		soml's decodeFile("/missing/" & unsafeKey)
		error "missing unsafe path was accepted"
	on error message number errorNumber
		check("missing file error number", errorNumber, -43)
		check("file diagnostic escapes terminal controls", message contains "\\u{1b}", true)
	end try
	try
		soml's toSeconds({class:SOML duration, value:"1" & character id 27})
		error "unsafe duration was accepted"
	on error message number errorNumber
		check("invalid duration helper number", errorNumber, -1703)
		check("duration diagnostic escapes terminal controls", message contains "\\u{1b}", true)
	end try
end testSafeErrors

on testCallerState()
	set previousDelimiters to AppleScript's text item delimiters
	set AppleScript's text item delimiters to {"sentinel", ":"}
	try
		try
			soml's decode("[1e9999]")
		end try
		check("decode failure preserves delimiters", AppleScript's text item delimiters, {"sentinel", ":"})
		try
			soml's encode({{class:SOML duration, value:"invalid"}})
		end try
		check("encode failure preserves delimiters", AppleScript's text item delimiters, {"sentinel", ":"})
		check("success after failures", soml's encodeCanonical(soml's decode("[0.25, {x: 'ok'}]")), "[" & linefeed & tab & "0.25" & linefeed & tab & "{" & linefeed & tab & tab & "x: 'ok'" & linefeed & tab & "}" & linefeed & "]" & linefeed)
	on error message number errorNumber
		set AppleScript's text item delimiters to previousDelimiters
		error message number errorNumber
	end try
	set AppleScript's text item delimiters to previousDelimiters
end testCallerState
