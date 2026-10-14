(*
Regressions for exact entry inspection, adversarial key groups, escaping, and output block boundaries.
*)
use AppleScript version "2.8"
use framework "Foundation"
use scripting additions
use soml : script "SOML"

property testCount : 0

on check(theName, actual, expected)
	set testCount to testCount + 1
	considering case, diacriticals, hyphens, punctuation and white space
		if actual is not expected then
			error theName & " failed"
		end if
	end considering
end check

on run
	set testCount to 0
	testEntryInspection()
	testLongStrings()
	testOutputBlocks()
	testCapitalKeys()
	testDictionaryKeys()
	testBlankBlockLines()
	return (testCount as text) & " improvement regression checks passed"
end run

on testEntryInspection()
	set unencodable to soml's fromEntries({{"bad" & return, 1}})
	check("entries does not validate nested key encodability", soml's entries({|nested|:unencodable}), {{"nested", unencodable}})
	check("entries exposes an unencodable key", soml's entries(unencodable), {{"bad" & return, 1}})
	check("entries exposes unsupported values", class of item 2 of item 1 of soml's entries({|unsupported|:me}), script)
	try
		soml's encode({|nested|:unencodable})
		error "unencodable key was written" number 99
	on error message number errorNumber
		check("writer still validates nested keys", errorNumber, 2)
		check("key failure names containing object", message contains "nested", true)
	end try
end testEntryInspection

on testLongStrings()
	set longText to "abc"
	repeat 14 times
		set longText to longText & longText
	end repeat
	repeat with suffix in {"\\", "\\\\", "\\\\\\", "'\\", "'\\\\", "'\"", "'" & tab}
		set theText to longText & contents of suffix
		check("long string suffix round trip", item 1 of soml's decode(soml's encode({theText})), theText)
	end repeat
	set fragile to character id 65279
	check("single fragile join", soml's joinTexts({fragile & "x"}, ","), fragile & "x")
	check("empty join", soml's joinTexts({}, ","), "")
	set unsafeText to longText & character id 27 & longText & character id 8238
	set sanitized to soml's sanitize(unsafeText)
	check("sanitization keeps long clean runs", sanitized, longText & "\\u{1b}" & longText & "\\u{202e}")
	check("JSON quoting keeps clean runs", soml's jsonQuote(longText & quote & tab), quote & longText & "\\\"\\t" & quote)
end testLongStrings

on testOutputBlocks()
	script Store
		property values : {}
	end script
	set theDate to current date
	set year of theDate to 2026
	set month of theDate to October
	set day of theDate to 14
	set time of theDate to 43200
	-- Scalars, floats, dates, and empty collections take different numbers of output pieces.
	repeat with step from 1 to 2100
		if step mod 4 = 0 then
			set end of Store's values to theDate
		else if step mod 4 = 1 then
			set end of Store's values to step / 10.0
		else if step mod 4 = 2 then
			set end of Store's values to "v" & step
		else
			set end of Store's values to {}
		end if
	end repeat
	set encoded to soml's encode(Store's values)
	set decoded to soml's decode(encoded)
	check("mixed pending values cross output blocks", count decoded, 2100)
	check("float before boundary", item 997 of decoded, 99.7)
	check("float after boundary", item 2001 of decoded, 200.1)
	check("date after boundary", soml's toDate(item 2100 of decoded), theDate)
	check("block output is canonical and stable", soml's encodeCanonical(decoded), encoded)
end testOutputBlocks

on testCapitalKeys()
	script Store
		property pairs : {}
	end script
	repeat with step from 1 to 600
		set end of Store's pairs to {"X-Header-" & step, step}
	end repeat
	set theObject to soml's fromEntries(Store's pairs)
	check("capital barred keys keep spelling and order", soml's entries(theObject), Store's pairs)
	check("capital keys survive writing", soml's entries(soml's decode(soml's encode(theObject))), Store's pairs)
end testCapitalKeys

on testDictionaryKeys()
	script Store
		property pairs : {}
	end script
	repeat with step from 1 to 300
		set end of Store's pairs to {"set-key-" & step, step}
	end repeat
	set end of Store's pairs to {"SET-KEY-300", -300}
	set end of Store's pairs to {character id 65279 & "bom", 1}
	set end of Store's pairs to {character id 65534 & "bom", 2}
	set end of Store's pairs to {character id 233, 3}
	set end of Store's pairs to {"e" & character id 769, 4}
	set theObject to soml's fromEntries(Store's pairs)
	check("large keys preserve case BOM and normalization differences", soml's entries(soml's decode(soml's encode(theObject))), Store's pairs)
	try
		soml's decode(soml's encode(theObject) & "'" & character id 65279 & "bom': 5")
		error "fragile duplicate was accepted" number 99
	on error message number errorNumber
		check("large fragile duplicate is rejected", errorNumber, 1)
	end try
end testDictionaryKeys

on testBlankBlockLines()
	set theText to "[" & linefeed & "'''" & linefeed & "  " & linefeed & "    first" & linefeed & tab & linefeed & "    second" & linefeed & " " & linefeed & "    '''" & linefeed & "]"
	check("blank lines need no closing indentation", item 1 of soml's decode(theText), "first" & linefeed & linefeed & "second")
end testBlankBlockLines
