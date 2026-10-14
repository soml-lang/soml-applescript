(*
Ordering invariants, long native string fast paths, and the shared JSON/SOML escape writer.
*)
use AppleScript version "2.8"
use framework "Foundation"
use scripting additions
use soml : script "SOML"

property checks : 0

on check(theName, actual, expected)
	set checks to checks + 1
	if actual is not expected then
		error theName & " failed"
	end if
end check

on run
	set checks to 0
	-- Repeated keys keep their input order across partial merge runs.
	repeat with keyCount in {0, 1, 2, 3, 7, 9, 17, 129, 257}
		script Store
			property codes : {}
			property expected : {}
		end script
		repeat with step from 1 to keyCount
			set end of Store's codes to {1000 + ((keyCount - step) mod 7)}
		end repeat
		repeat with bucket from 0 to 6
			repeat with step from 1 to keyCount
				if item 1 of item step of Store's codes = 1000 + bucket then
					set end of Store's expected to step
				end if
			end repeat
		end repeat
		check("stable merge order at " & keyCount, soml's sortedCodeOrder(Store's codes), Store's expected)
	end repeat
	set prefixText to "a"
	repeat 14 times
		set prefixText to prefixText & prefixText
	end repeat
	set prefixCodes to soml's codePoints(prefixText)
	set earlierCodes to prefixCodes & {97}
	set laterCodes to prefixCodes & {98}
	check("long prefix forward comparison", soml's compareCodes(earlierCodes, laterCodes), -1)
	check("long prefix backward comparison", soml's compareCodes(laterCodes, earlierCodes), 1)
	check("long equal comparison", soml's compareCodes(earlierCodes, earlierCodes), 0)
	check("shorter shared prefix", soml's compareCodes(prefixCodes, earlierCodes), -1)
	check("stable long key sort", soml's sortedCodeOrder({laterCodes, earlierCodes, prefixCodes, earlierCodes}), {3, 2, 4, 1})
	check("scalar order across UTF-16 boundary", soml's sortedCodeOrder({{65536}, {57344}, {128512}, {65535}}), {2, 4, 1, 3})
	set longText to text 1 thru 1024 of prefixText
	-- A native inverted character set does not see lone surrogates, so a long key must also be valid ASCII.
	set nativeAstral to current application's NSString's stringWithString:(character id 128512)
	set surrogateTexts to {(nativeAstral's substringToIndex:1) as text, (nativeAstral's substringFromIndex:1) as text}
	repeat with surrogateText in surrogateTexts
		set malformedKey to longText & contents of surrogateText & "x"
		repeat with isCanonical in {false, true}
			set checks to checks + 1
			try
				set taggedObject to {class:SOML object, entries:{{malformedKey, 1}}}
				if isCanonical then
					soml's encodeCanonical(taggedObject)
				else
					soml's encode(taggedObject)
				end if
				error "Encoded a long key with a lone surrogate" number 99
			on error message number errorNumber
				if errorNumber is not 2 then
					error message number errorNumber
				end if
			end try
			set checks to checks + 1
			try
				if isCanonical then
					soml's encodeCanonical({malformedKey})
				else
					soml's encode({malformedKey})
				end if
				error "Encoded a long string with a lone surrogate" number 99
			on error message number errorNumber
				if errorNumber is not 2 then
					error message number errorNumber
				end if
			end try
		end repeat
		check("native lone-surrogate key", soml's isBareKeyText(malformedKey, missing value), false)
	end repeat
	repeat with prefix in {"", character id 65279, character id 65534, character id 769, "🦄"}
		set theText to contents of prefix & longText & "é🦄"
		set expected to "[" & linefeed & tab & "'" & theText & "'" & linefeed & "]" & linefeed
		check("long literal Unicode output", id of soml's encode({theText}), id of expected)
		check("long literal Unicode round trip", id of item 1 of soml's decode(expected), id of theText)
	end repeat
	repeat with suffix in {quote, "'", tab, linefeed, character id 127, "\\"}
		set theText to longText & contents of suffix
		check("long escape fallback", id of item 1 of soml's decode(soml's encode({theText})), id of theText)
	end repeat
	check("native bare key", soml's isBareKeyText(longText & "_0-Z", missing value), true)
	repeat with suffix in {"é", ".", ":", "🦄", character id 65279}
		check("native non-ASCII bare suffix", soml's isBareKeyText(longText & contents of suffix, missing value), false)
	end repeat
	-- JSON diagnostics and SOML values share escaping, but use different control spellings.
	set theText to quote & "\\" & tab & linefeed & (character id 8) & (character id 12) & (character id 127)
	check("JSON control dialect", id of soml's jsonQuote(theText), id of (quote & "\\\"\\\\\\t\\n\\b\\f" & character id 127 & quote))
	check("SOML control dialect", id of soml's formatStringCodes(theText, id of theText, ""), id of (quote & "\\\"\\\\\\t\\n\\u{8}\\u{c}\\u{7f}" & quote))
	return (checks as text) & " runtime utility checks passed"
end run
