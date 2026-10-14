(*
Mixed deferred values, repeated conversion batches, and exact duplicate detection after case-collision fallback exercise independent writer and construction invariants.
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
	testCaseCollisionDuplicates()
	testNativeLabelAliases()
	testRecordDisguisedAsEntry()
	testRecordsDisguisedAsEntryLists()
	testKeysAboveRecordLimit()
	testDeferredOutputBlocks()
	testRepeatedFloatBatches()
	testRepeatedNativeLabels()
	testLongDiagnosticSanitization()
	testCaseFoldingPrefixes()
	return (checks as text) & " writer refinement checks passed"
end run

on testCaseCollisionDuplicates()
	script Store
		property pairs : {{"Refinement-Collision", 1}, {"refinement-collision", 2}}
	end script
	repeat with step from 1 to 300
		set end of Store's pairs to {"refinement-key-" & step, contents of step}
	end repeat
	set taggedObject to soml's fromEntries(Store's pairs)
	check("large case collision stays tagged", class of taggedObject, SOML object)
	check("large case collision retains exact entries", soml's entries(taggedObject), Store's pairs)
	set end of Store's pairs to {"refinement-key-300", 999}
	repeat with operation in {"construct", "encode", "canonical"}
		try
			if contents of operation is "construct" then
				soml's fromEntries(Store's pairs)
			else if contents of operation is "encode" then
				soml's encode({class:SOML object, entries:Store's pairs})
			else
				soml's encodeCanonical({class:SOML object, entries:Store's pairs})
			end if
			error "Accepted a duplicate after a case collision" number 99
		on error message number errorNumber
			check("duplicate after case collision error", errorNumber, 2)
			check("duplicate after case collision identifies key", message contains "refinement-key-300", true)
		end try
	end repeat
end testCaseCollisionDuplicates

on testKeysAboveRecordLimit()
	script Store
		property pairs : {}
	end script
	repeat with step from 1 to 4100
		set end of Store's pairs to {"refinement-limit-" & step, contents of step}
	end repeat
	set composedKey to "refinement-" & (character id 233)
	set decomposedKey to "refinement-e" & (character id 769)
	set fragileKey to (character id 65279) & "refinement-limit"
	set end of Store's pairs to {composedKey, "composed"}
	set end of Store's pairs to {decomposedKey, "decomposed"}
	set end of Store's pairs to {fragileKey, "fragile"}
	set made to soml's fromEntries(Store's pairs)
	check("above-limit objects stay tagged", class of made, SOML object)
	set actualPairs to soml's entries(made)
	check("above-limit objects retain all entries", count actualPairs, 4103)
	check("above-limit objects retain composed keys", id of item 1 of item 4101 of actualPairs, id of composedKey)
	check("above-limit objects retain decomposed keys", id of item 1 of item 4102 of actualPairs, id of decomposedKey)
	check("above-limit objects retain byte order prefix", id of item 1 of item 4103 of actualPairs, id of fragileKey)
	set end of Store's pairs to {fragileKey, "duplicate"}
	try
		soml's fromEntries(Store's pairs)
		error "Accepted an above-limit duplicate with a byte order prefix" number 99
	on error message number errorNumber
		check("above-limit duplicate error", errorNumber, 2)
		check("above-limit duplicate identifies key", message contains "refinement-limit", true)
	end try
end testKeysAboveRecordLimit

on testRecordsDisguisedAsEntryLists()
	repeat with fakeList in {{class:list}, {class:list, pair:{"a", 1}}, {class:list, firstPair:{"a", 1}, lastPair:{"b", 2}}}
		set actualFakeList to contents of fakeList
		repeat with usesReference in {false, true}
			try
				if contents of usesReference then
					soml's fromEntries(fakeList)
				else
					soml's fromEntries(actualFakeList)
				end if
				error "Accepted a record disguised as the fromEntries list" number 99
			on error message number errorNumber
				check("disguised outer lists use wrong-type errors", errorNumber, -1703)
				check("disguised outer lists identify the argument", message starts with "fromEntries() expects a list", true)
			end try
		end repeat
		try
			soml's entries({class:SOML object, entries:actualFakeList})
			error "Returned a record disguised as tagged object entries" number 99
		on error message number errorNumber
			check("entries rejects a disguised entry list", errorNumber, 2)
		end try
	end repeat
	check("actual empty list remains supported", soml's entries(soml's fromEntries({})), {})
	set singletonPairs to {{"refinement-singleton", 17}}
	repeat with referencedPairs in {singletonPairs}
		check("referenced singleton list remains supported", soml's entries(soml's fromEntries(referencedPairs)), singletonPairs)
	end repeat
end testRecordsDisguisedAsEntryLists

on testRecordDisguisedAsEntry()
	set disguisedPair to {class:list, a:"key"}
	set disguisedEntries to {class:list, a:{"key", 1}}
	repeat with theValue in {{class:SOML object, entries:{disguisedPair}}, {class:SOML object, entries:disguisedEntries}}
		repeat with isCanonical in {false, true}
			try
				if contents of isCanonical then
					soml's encodeCanonical(contents of theValue)
				else
					soml's encode(contents of theValue)
				end if
				error "Accepted a record disguised as tagged object entry lists" number 99
			on error message number errorNumber
				check("disguised entry lists use unsupported-value errors", errorNumber, 2)
			end try
		end repeat
	end repeat
end testRecordDisguisedAsEntry

on testNativeLabelAliases()
	repeat with theValue in {{name:1, |name|:2}, {nested:{name:1, |name|:2}}}
		repeat with isCanonical in {false, true}
			try
				if contents of isCanonical then
					soml's encodeCanonical(contents of theValue)
				else
					soml's encode(contents of theValue)
				end if
				error "Accepted keyword and user labels with the same SOML spelling" number 99
			on error message number errorNumber
				check("native label aliases error", errorNumber, 2)
				check("native label aliases identify duplicate", message contains "Duplicate key name", true)
			end try
		end repeat
	end repeat
end testNativeLabelAliases

on testDeferredOutputBlocks()
	script Store
		property values : {}
	end script
	set nativeDate to soml's toDate({class:SOML instant, value:"1969-12-31T23:59:59Z"})
	repeat with step from 1 to 1450
		set end of Store's values to {contents of step, step + 0.25, nativeDate}
	end repeat
	repeat with isCanonical in {false, true}
		if contents of isCanonical then
			set encoded to soml's encodeCanonical(Store's values)
		else
			set encoded to soml's encode(Store's values)
		end if
		set decoded to soml's decode(encoded)
		check("deferred output retains every nested item", count decoded, 1450)
		repeat with itemIndex in {1, 255, 256, 257, 799, 800, 801, 1333, 1450}
			set itemIndex to contents of itemIndex
			set actualItem to item itemIndex of decoded
			check("deferred output integer association", item 1 of actualItem, itemIndex)
			check("deferred output real association", item 2 of actualItem, itemIndex + 0.25)
			check("deferred output date association", value of item 3 of actualItem, "1969-12-31T23:59:59Z")
		end repeat
	end repeat
end testDeferredOutputBlocks

on testRepeatedFloatBatches()
	set sourceParts to {}
	repeat with step from 1 to 80
		-- A case-colliding object is converted when it closes, before the next batch or infinity is read.
		set end of sourceParts to "{Refinement-Batch: " & step & ".125, refinement-batch: -" & step & ".5}"
	end repeat
	set sourceText to "[infinity, " & soml's joinTexts(sourceParts, ", ") & ", -infinity]"
	set decoded to soml's decode(sourceText)
	check("repeated float batches retain collection length", count decoded, 82)
	repeat with step from 1 to 80
		set thePairs to soml's entries(item (step + 1) of decoded)
		check("repeated batch first real", item 2 of item 1 of thePairs, step + 0.125)
		check("repeated batch second real", item 2 of item 2 of thePairs, -step - 0.5)
	end repeat
	set encoded to soml's encode(decoded)
	check("infinity survives repeated float batches", encoded starts with "[" & linefeed & tab & "infinity" & linefeed, true)
	check("negative infinity survives repeated float batches", encoded ends with tab & "-infinity" & linefeed & "]" & linefeed, true)
end testRepeatedFloatBatches

on testRepeatedNativeLabels()
	script Store
		property nativeRecords : {}
	end script
	repeat with step from 1 to 300
		set end of Store's nativeRecords to {repeated:contents of step, |Repeated-Case|:"value-" & step}
	end repeat
	set made to soml's fromEntries({{"record-list", Store's nativeRecords}})
	check("repeated native labels retain native root", class of made, record)
	set actualRecords to item 2 of item 1 of soml's entries(made)
	check("repeated native labels retain all records", count actualRecords, 300)
	repeat with itemIndex in {1, 150, 300}
		set itemIndex to contents of itemIndex
		check("repeated native labels preserve spellings and associations", soml's entries(item itemIndex of actualRecords), {{"repeated", itemIndex}, {"Repeated-Case", "value-" & itemIndex}})
	end repeat
end testRepeatedNativeLabels

on testLongDiagnosticSanitization()
	set longText to "plain"
	repeat 8 times
		set longText to longText & longText
	end repeat
	check("long safe diagnostic text remains exact", id of soml's sanitize(longText & tab), id of (longText & tab))
	repeat with dangerousCode in {0, 8, 10, 13, 27, 127, 155, 173, 1564, 8203, 8238, 8294, 65279}
		set dangerousCode to contents of dangerousCode
		set theKey to longText & (character id dangerousCode) & "tail"
		try
			soml's encode({class:SOML object, entries:{{theKey, me}}})
			error "Accepted an unsupported script value" number 99
		on error message number errorNumber
			check("long diagnostic uses the unsupported-value error", errorNumber, 2)
			check("long diagnostic escapes dangerous code", (soml's codePoints(message)) contains dangerousCode, false)
		end try
	end repeat
end testLongDiagnosticSanitization

on testCaseFoldingPrefixes()
	set longPrefix to "lowercase-"
	repeat 7 times
		set longPrefix to longPrefix & longPrefix
	end repeat
	set cases to {{"", ""}, {longPrefix, longPrefix}, {"A" & longPrefix, "a" & longPrefix}, {longPrefix & "Z", longPrefix & "z"}, {longPrefix & "AZ" & longPrefix, longPrefix & "az" & longPrefix}, {longPrefix & "ÉΣİ", longPrefix & "ÉΣİ"}, {longPrefix & "A" & (character id 769), longPrefix & "a" & (character id 769)}}
	repeat with theCase in cases
		set inputCodes to soml's codePoints(item 1 of theCase)
		set expectedCodes to soml's codePoints(item 2 of theCase)
		check("folding changes only ASCII capitals after any prefix", soml's foldCase(inputCodes), expectedCodes)
		check("folding preserves caller input", inputCodes, soml's codePoints(item 1 of theCase))
	end repeat
end testCaseFoldingPrefixes
