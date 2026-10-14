(*
Canonical key sorting must keep values and display nodes associated with their exact Unicode keys, without mutating the input. Sorted and shuffled objects exercise both writer paths.
*)
use AppleScript version "2.8"
use scripting additions
use soml : script "SOML"

property checks : 0

on check(theName, actual, expected)
	set checks to checks + 1
	considering case, diacriticals, hyphens, punctuation and white space
		if actual is not expected then
			error theName & " failed" number 99
		end if
	end considering
end check

on run
	set checks to 0
	testEmptyCollections()
	testUnicodeOrder()
	testCanonicalAssociations()
	testSortPermutations()
	testDurationPreviews()
	return (checks as text) & " writer ordering checks passed"
end run

on testEmptyCollections()
	set emptyObject to {class:SOML object, entries:{}}
	repeat with usesCanonical in {false, true}
		if contents of usesCanonical then
			check("empty root object", soml's encodeCanonical(emptyObject), "{}" & linefeed)
			check("empty root array", soml's encodeCanonical({}), "[]" & linefeed)
			set encoded to soml's encodeCanonical({emptyObject, {}})
		else
			check("empty root object", soml's encode(emptyObject), "{}" & linefeed)
			check("empty root array", soml's encode({}), "[]" & linefeed)
			set encoded to soml's encode({emptyObject, {}})
		end if
		check("nested empty collection kinds", encoded, "[" & linefeed & tab & "{}" & linefeed & tab & "[]" & linefeed & "]" & linefeed)
	end repeat
end testEmptyCollections

on testUnicodeOrder()
	set keys to {"", "A", "a", "a-", "a0", "aa", "e" & (character id 769), character id 233, character id 65533, character id 65536, character id 128512}
	set sortedPairs to {}
	repeat with step from 1 to count keys
		set end of sortedPairs to {item step of keys, contents of step}
	end repeat
	set expected to soml's encode({class:SOML object, entries:sortedPairs})
	check("canonical sorted scalar order", soml's encodeCanonical({class:SOML object, entries:sortedPairs}), expected)
	check("canonical reverse scalar order", soml's encodeCanonical({class:SOML object, entries:reverse of sortedPairs}), expected)
	check("canonical input entries remain in order", soml's entries({class:SOML object, entries:sortedPairs}), sortedPairs)
end testUnicodeOrder

on testCanonicalAssociations()
	set nativeDate to soml's toDate({class:SOML instant, value:"1970-01-01T00:00:01Z"})
	set pairs to {{"a", {nested:1}}, {"b", {2, {deeper:"value"}}}, {"c", 3.25}, {"d", nativeDate}, {"e", {class:SOML duration, value:"1m2s"}}, {"f", missing value}}
	set expected to soml's encode({class:SOML object, entries:pairs})
	set shuffledPairs to {item 4 of pairs, item 2 of pairs, item 6 of pairs, item 1 of pairs, item 5 of pairs, item 3 of pairs}
	set shuffled to {class:SOML object, entries:shuffledPairs}
	repeat 3 times
		check("canonical nested and deferred associations", soml's encodeCanonical(shuffled), expected)
		check("canonical preserves original entries", soml's entries(shuffled), shuffledPairs)
	end repeat
	check("canonical sorted nested associations", soml's encodeCanonical({class:SOML object, entries:pairs}), expected)
end testCanonicalAssociations

on testSortPermutations()
	set expected to {1, 2, 3, 4, 5, 6, 7, 8, 9}
	repeat with permutation in {{1, 2, 3, 4, 5, 6, 7, 8, 9}, {9, 8, 7, 6, 5, 4, 3, 2, 1}, {1, 3, 5, 7, 9, 2, 4, 6, 8}, {2, 1, 4, 3, 6, 5, 8, 7, 9}, {1, 2, 3, 5, 4, 6, 7, 8, 9}}
		set codes to {}
		repeat with theNumber in permutation
			set end of codes to {contents of theNumber}
		end repeat
		copy codes to originalCodes
		set order to soml's sortedCodeOrder(codes)
		set actual to {}
		repeat with theIndex in order
			set end of actual to item 1 of item (contents of theIndex) of codes
		end repeat
		check("sort permutations", actual, expected)
		check("sort leaves source untouched", codes, originalCodes)
	end repeat
	check("empty sort", soml's sortedCodeOrder({}), {})
	check("singleton sort", soml's sortedCodeOrder({{42}}), {1})
	check("equal key sort is stable", soml's sortedCodeOrder({{2}, {1}, {1}, {2}, {1}}), {2, 3, 5, 1, 4})
end testSortPermutations

(*
The writer and public duration helper must retain bounded, UTF-16-based previews when the invalid remainder is long.
*)
on testDurationPreviews()
	set longSuffix to "z"
	repeat 14 times
		set longSuffix to longSuffix & longSuffix
	end repeat
	set astralText to character id 128512
	set fiveAstralCharacters to astralText & astralText & astralText & astralText & astralText
	repeat with theCase in {{"abcdefghijk" & longSuffix, "abcdefghij…"}, {"1s?" & longSuffix, "?zzzzzzzzz…"}, {fiveAstralCharacters & astralText & longSuffix, fiveAstralCharacters & "…"}}
		set taggedDuration to {class:SOML duration, value:item 1 of theCase}
		repeat with operation in {"encode", "toSeconds"}
			try
				if contents of operation is "encode" then
					soml's encode({duration:taggedDuration})
				else
					soml's toSeconds(taggedDuration)
				end if
				error "Accepted an invalid duration" number 99
			on error message number errorNumber
				set expectedError to 2
				if contents of operation is "toSeconds" then
					set expectedError to -1703
				end if
				check("duration failure preserves error number", errorNumber, expectedError)
				check("duration expected-number preview", message contains "expected a number at “" & item 2 of theCase & "”", true)
				check("duration diagnostic remains bounded", length of message < 220, true)
			end try
		end repeat
	end repeat
end testDurationPreviews
