(*
Native keyword labels, caller text comparison settings, and value classes must survive entry inspection and construction.
*)
use AppleScript version "2.8"
use scripting additions
use soml : script "SOML"

property testCount : 0

on check(theName, actual, expected)
	set testCount to testCount + 1
	considering case, diacriticals, hyphens, punctuation and white space
		if actual is not expected then
			error theName & " failed" number 99
		end if
	end considering
end check

on run
	set testCount to 0
	testKeywordLabels()
	testCallerComparisons()
	testNativeValues()
	testSpecialLabels()
	testUnicodeKeyLookups()
	return (testCount as text) & " native record checks passed"
end run

on testKeywordLabels()
	-- Every label here is a compilable native AppleScript or scripting addition label. Compilation failures must fail the test.
	repeat with labelName in {"name", "id", "version", "length", "contents", "properties", "text item delimiters", "POSIX path", "button returned", "text returned", "gave up", "bounds", "selection", "result", "collating", "copies", "detailed", "string", "index", "size", "modification date", "creation date", "file type", "file creator", "locked", "visible", "busy status", "folder", "alias", "port", "host"}
		set labelName to contents of labelName
		set nativeRecord to run script "use scripting additions" & linefeed & "return {" & labelName & ":1}"
		set expectedKey to labelName
		if labelName contains " " then
			set expectedKey to "'" & labelName & "'"
		end if
		set expectedText to expectedKey & ": 1" & linefeed
		check(labelName & " entry spelling and value", soml's entries(nativeRecord), {{labelName, 1}})
		check(labelName & " normal output", id of soml's encode(nativeRecord), id of expectedText)
		check(labelName & " canonical output", id of soml's encodeCanonical(nativeRecord), id of expectedText)
		check(labelName & " decoded entry", soml's entries(soml's decode(expectedText)), {{labelName, 1}})
	end repeat
end testKeywordLabels

on testCallerComparisons()
	set decomposedKey to "e" & character id 769
	set cases to {{"'a-b': 'x'" & linefeed & "ab: 'y'" & linefeed & "'a b': 'z'", "'a b': 'z'" & linefeed & "a-b: 'x'" & linefeed & "ab: 'y'" & linefeed}, {"'é': 1" & linefeed & "'e': 2" & linefeed & "'" & decomposedKey & "': 3", "e: 2" & linefeed & "'" & decomposedKey & "': 3" & linefeed & "'é': 1" & linefeed}, {"'Class': 'x'" & linefeed & "class: 'y'", "Class: 'x'" & linefeed & "class: 'y'" & linefeed}}
	set originalPairs to {{"a-b", 1}, {"ab", 2}, {"a b", 3}, {"a", 4}, {"A", 5}, {"é", 6}, {"e", 7}, {decomposedKey, 8}, {"", 9}, {" ", 10}}
	set literalRecord to {|a-b|:1, ab:2, |a b|:3, |é|:4, |e|:5}
	set literalEntries to {{"a-b", 1}, {"ab", 2}, {"a b", 3}, {"é", 4}, {"e", 5}}
	ignoring case, diacriticals, hyphens, punctuation and white space
		repeat with theCase in cases
			check("ignoring caller comparisons preserves canonical keys", id of soml's encodeCanonical(soml's decode(item 1 of theCase)), id of item 2 of theCase)
		end repeat
		check("ignoring caller comparisons preserves constructed keys", soml's entries(soml's fromEntries(originalPairs)), originalPairs)
		check("ignoring caller comparisons preserves native labels", soml's entries(literalRecord), literalEntries)
	end ignoring
	considering case, diacriticals, hyphens, punctuation and white space
		repeat with theCase in cases
			check("considering caller comparisons preserves canonical keys", id of soml's encodeCanonical(soml's decode(item 1 of theCase)), id of item 2 of theCase)
		end repeat
		check("considering caller comparisons preserves constructed keys", soml's entries(soml's fromEntries(originalPairs)), originalPairs)
		check("considering caller comparisons preserves native labels", soml's entries(literalRecord), literalEntries)
	end considering
end testCallerComparisons

(*
Distinct Unicode labels retain their exact spelling and value association, including case variants and canonically equivalent spellings. Native records must also provide each value through its own barred label.
*)
on testUnicodeKeyLookups()
	set keyCases to {{"É", "é"}, {"Σ", "σ"}, {"σ", "ς"}, {"А", "а"}, {"İ", "i"}, {"K", "K"}, {"Å", "A" & character id 778}, {"é", "e" & character id 769}}
	repeat with caseIndex from 1 to count keyCases
		set keyNames to item caseIndex of keyCases
		set expectedValues to {11, 22}
		set made to soml's fromEntries({{item 1 of keyNames, 11}, {item 2 of keyNames, 22}})
		set foundPairs to soml's entries(made)
		check("Unicode key pair count " & caseIndex, count foundPairs, 2)
		repeat with pairIndex from 1 to 2
			check("Unicode key spelling " & caseIndex & ":" & pairIndex, id of item 1 of item pairIndex of foundPairs, id of item pairIndex of keyNames)
			check("Unicode key value " & caseIndex & ":" & pairIndex, item 2 of item pairIndex of foundPairs, item pairIndex of expectedValues)
		end repeat
		if class of made is record then
			set lookupSource to "on run {nativeRecord}" & linefeed & "return {|" & item 1 of keyNames & "| of nativeRecord, |" & item 2 of keyNames & "| of nativeRecord}" & linefeed & "end run"
			set foundValues to run script lookupSource with parameters {made}
			check("Unicode native label lookup " & caseIndex, foundValues, expectedValues)
		end if
	end repeat
end testUnicodeKeyLookups

on testNativeValues()
	-- AppleScript can produce these integers arithmetically, but an Apple event would change them to reals.
	set positiveInteger to 536870911 + 1
	set negativeInteger to -positiveInteger - 1
	set nativeDate to current date
	set day of nativeDate to 1
	set year of nativeDate to 2026
	set month of nativeDate to October
	set day of nativeDate to 14
	set time of nativeDate to 12345
	set nestedIntegers to {positiveInteger, {nested:negativeInteger}}
	set ordinaryRecord to {name:"n", |Class|:"ordinary", ratio:0.0}
	set taggedInteger to {class:SOML int, value:"9223372036854775807"}
	set taggedDuration to {class:SOML duration, value:"1h"}
	set taggedInstant to {class:SOML instant, value:"2026-10-14T12:00:00Z"}
	set taggedObject to {class:SOML object, entries:{{"A", 1}, {"a", 2}}}
	set cases to {{missing value, missing value, class of missing value}, {true, true, boolean}, {false, false, boolean}, {0, 0, integer}, {0.0, 0.0, real}, {positiveInteger, 536870911 + 1, integer}, {negativeInteger, -positiveInteger - 1, integer}, {nativeDate, nativeDate, date}, {nestedIntegers, {536870911 + 1, {nested:-positiveInteger - 1}}, list}, {ordinaryRecord, {name:"n", |Class|:"ordinary", ratio:0.0}, record}, {taggedInteger, {class:SOML int, value:"9223372036854775807"}, SOML int}, {taggedDuration, {class:SOML duration, value:"1h"}, SOML duration}, {taggedInstant, {class:SOML instant, value:"2026-10-14T12:00:00Z"}, SOML instant}, {taggedObject, {class:SOML object, entries:{{"A", 1}, {"a", 2}}}, SOML object}}
	set caseIndex to 0
	repeat with theCase in cases
		set caseIndex to caseIndex + 1
		set made to soml's fromEntries({{"Native-Value", item 1 of theCase}})
		set found to item 2 of item 1 of soml's entries(made)
		check("native entry value", found, item 2 of theCase)
		check("native entry class " & caseIndex, class of found, item 3 of theCase)
	end repeat
	set made to soml's fromEntries({{"nested", nestedIntegers}})
	set found to item 2 of item 1 of soml's entries(made)
	check("nested positive integer class", class of item 1 of found, integer)
	check("nested negative integer class", class of nested of item 2 of found, integer)
	check("nested native integer output", id of soml's encode(found), id of ("[" & linefeed & tab & "536870912" & linefeed & tab & "{" & linefeed & tab & tab & "nested: -536870913" & linefeed & tab & "}" & linefeed & "]" & linefeed))
	set made to soml's fromEntries({{"ordinary", ordinaryRecord}})
	check("ordinary class key stays a user label", soml's entries(item 2 of item 1 of soml's entries(made)), {{"name", "n"}, {"Class", "ordinary"}, {"ratio", 0.0}})
end testNativeValues

on testSpecialLabels()
	-- Metadata and display wrapper names are ordinary keys, including their separately registered case variants.
	repeat with keyText in {"entries", "Entries", "SOMLValue", "somlvalue"}
		set keyText to contents of keyText
		repeat with methodName in {"decode", "construct"}
			set theName to keyText & " " & methodName
			if contents of methodName is "decode" then
				set made to soml's decode(keyText & ": [7, 0.125, {inner: 3}]" & linefeed)
			else
				set made to soml's fromEntries({{keyText, {7, 0.125, {inner:3}}}})
			end if
			set pairs to soml's entries(made)
			check(theName & " entry count", count pairs, 1)
			check(theName & " exact key", id of item 1 of item 1 of pairs, id of keyText)
			set values to item 2 of item 1 of pairs
			check(theName & " nested values", {item 1 of values, item 2 of values, item 2 of item 1 of soml's entries(item 3 of values)}, {7, 0.125, 3})
			check(theName & " real class", class of item 2 of values, real)
			set expectedText to keyText & ": [" & linefeed & tab & "7" & linefeed & tab & "0.125" & linefeed & tab & "{" & linefeed & tab & tab & "inner: 3" & linefeed & tab & "}" & linefeed & "]" & linefeed
			check(theName & " canonical output", id of soml's encodeCanonical(made), id of expectedText)
		end repeat
	end repeat
end testSpecialLabels
