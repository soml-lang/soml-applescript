(*
Boundary regressions where the reader, the writer, and fromEntries() switch strategies: duplicate-key checks at 256 keys, and display text with long runs of backslashes.

	make thresholds
*)
use AppleScript version "2.8"
use scripting additions
use soml : script "SOML"

property failures : {}
property checks : 0

on run
	set failures to {}
	set checks to 0
	testReaderDuplicateKeys()
	testFromEntriesDuplicateKeys()
	testWriterDuplicateKeys()
	testDisplayBackslashes()
	if failures is not {} then
		error soml's joinTexts(failures, linefeed)
	end if
	return (checks as text) & " threshold checks passed"
end run

on check(theName, actual, expected)
	set checks to checks + 1
	considering case, diacriticals, hyphens, punctuation and white space
		if actual is not expected then
			set end of failures to theName
		end if
	end considering
end check

on numberedKeys(theCount)
	script Store
		property parts : {}
	end script
	repeat with step from 1 to theCount
		set end of Store's parts to "key-" & step & ": " & step
	end repeat
	return soml's joinTexts(Store's parts, linefeed)
end numberedKeys

on numberedPairs(theCount)
	script Store
		property pairs : {}
	end script
	repeat with step from 1 to theCount
		set end of Store's pairs to {"key-" & step, step}
	end repeat
	return Store's pairs
end numberedPairs

-- The reader checks the first 256 keys of an object in lists, and moves them to sets for the 257th key.
on testReaderDuplicateKeys()
	repeat with duplicateCase in {{255, "key-1"}, {256, "key-1"}, {300, "key-1"}, {300, "key-256"}, {257, "key-257"}}
		set {keyCount, duplicateKey} to contents of duplicateCase
		set theName to "reader duplicate " & duplicateKey & " after " & keyCount & " keys"
		try
			soml's decode(numberedKeys(keyCount) & linefeed & duplicateKey & ": 0")
			check(theName & " was accepted", true, false)
		on error message number errorNumber from details
			check(theName & " error number", errorNumber, 1)
			check(theName & " position", {|line| of details, |column| of details}, {keyCount + 1, 1})
		end try
	end repeat
	-- A case variant of a key that was moved to the sets still makes the object tagged.
	repeat with keyCount in {255, 256, 300}
		set config to soml's decode(numberedKeys(keyCount) & linefeed & "KEY-1: 0")
		check("reader case variant after " & keyCount & " keys is tagged", class of config, SOML object)
		check("reader case variant after " & keyCount & " keys keeps order", item 1 of item -1 of soml's entries(config), "KEY-1")
	end repeat
	-- A key that starts with U+FEFF keeps its spelling when it is moved to the sets.
	set fragileKey to (character id 65279) & "bom"
	try
		soml's decode("'" & fragileKey & "': 0" & linefeed & numberedKeys(300) & linefeed & "'" & fragileKey & "': 1")
		check("reader fragile duplicate across the sets was accepted", true, false)
	on error message number errorNumber from details
		check("reader fragile duplicate across the sets error number", errorNumber, 1)
		check("reader fragile duplicate across the sets position", |line| of details, 302)
	end try
end testReaderDuplicateKeys

-- fromEntries() checks up to 256 pairs in lists and more by sorting.
on testFromEntriesDuplicateKeys()
	repeat with pairCount in {255, 256}
		set pairs to numberedPairs(pairCount)
		set theName to "fromEntries duplicate in " & (pairCount + 1) & " pairs"
		try
			soml's fromEntries(pairs & {{"key-1", 0}})
			check(theName & " was accepted", true, false)
		on error message number errorNumber
			check(theName & " error number", errorNumber, 2)
			check(theName & " names the key", message contains "Duplicate key key-1", true)
		end try
		set variantPairs to pairs & {{"KEY-1", 0}}
		set made to soml's fromEntries(variantPairs)
		check("fromEntries case variant in " & (pairCount + 1) & " pairs is tagged", class of made, SOML object)
		check("fromEntries case variant in " & (pairCount + 1) & " pairs keeps entries", soml's entries(made), variantPairs)
	end repeat
end testFromEntriesDuplicateKeys

-- The writer checks up to 256 keys of an object in lists, and more, or any for canonical output, by sorting.
on testWriterDuplicateKeys()
	repeat with pairCount in {255, 256}
		set theObject to {class:SOML object, entries:numberedPairs(pairCount) & {{"key-1", 0}}}
		repeat with isCanonical in {false, true}
			set isCanonical to contents of isCanonical
			set theName to "writer duplicate in " & (pairCount + 1) & " entries, canonical " & isCanonical
			try
				if isCanonical then
					soml's encodeCanonical(theObject)
				else
					soml's encode(theObject)
				end if
				check(theName & " was accepted", true, false)
			on error message number errorNumber
				check(theName & " error number", errorNumber, 2)
				check(theName & " names the key", message contains "Duplicate key key-1", true)
			end try
		end repeat
	end repeat
end testWriterDuplicateKeys

-- The writer reads AppleScript's display of a value, where an odd run of backslashes before a quote means the quote is part of the string. A run longer than 512 characters is counted in parts.
on testDisplayBackslashes()
	repeat with backslashCount in {255, 256, 257, 300}
		set backslashes to ""
		repeat backslashCount times
			set backslashes to backslashes & "\\"
		end repeat
		repeat with theText in {backslashes, backslashes & quote & "x", backslashes & quote & "x" & backslashes}
			set theText to contents of theText
			set theName to "display backslashes " & backslashCount & " in " & (length of theText) & " characters"
			try
				check(theName & " list round trip", id of item 1 of soml's decode(soml's encode({theText, "after"})), id of theText)
				check(theName & " record round trip", soml's entries(soml's decode(soml's encode({|value|:theText, |after|:quote}))), {{"value", theText}, {"after", quote}})
			on error message number errorNumber
				set end of failures to theName & ": " & errorNumber & " " & message
			end try
		end repeat
	end repeat
end testDisplayBackslashes
