(*
Opaque record values must survive construction even when their `class` property claims to be a scalar or a list. The same record cannot serve as a {key, value} pair, and malformed pairs must report the documented wrong-type error.
*)
use AppleScript version "2.8"
use scripting additions
use soml : script "SOML"
property failures : {}
property testCount : 0

on expectInvalidPair(theName, theEntries, expectedIndex)
	set testCount to testCount + 1
	try
		soml's fromEntries(theEntries)
		set end of failures to theName & ": accepted a malformed entry pair"
	on error message number errorNumber
		if errorNumber is not -1703 or message does not start with ("fromEntries() expects a list of {key, value} lists with text keys, but item " & expectedIndex & " is ") then
			set end of failures to theName & ": expected the wrong-type error at item " & expectedIndex & ", got " & errorNumber & " " & message
		end if
	end try
end expectInvalidPair

on testPairValidation()
	set opaquePairs to {{key:"first", class:list}, {class:list, key:"second"}}
	set expectedFields to {{"first", list}, {list, "second"}}
	repeat with caseIndex from 1 to count opaquePairs
		set opaquePair to item caseIndex of opaquePairs
		if class of opaquePair is not list or (count opaquePair) is not 2 or (opaquePair as record as list) is not item caseIndex of expectedFields then
			error "Pair fixture lost its physical fields or reported list class"
		end if
		repeat with badIndex from 1 to 2
			set suppliedEntries to {opaquePair}
			if badIndex is 2 then
				set suppliedEntries to {{"valid-first", 7}, opaquePair}
			end if
			expectInvalidPair("Opaque pair " & caseIndex & " direct item " & badIndex, suppliedEntries, badIndex)
			repeat with referencedEntries in {suppliedEntries}
				expectInvalidPair("Opaque pair " & caseIndex & " root reference item " & badIndex, referencedEntries, badIndex)
			end repeat
		end repeat
		-- Pair validation must not coerce the same opaque record when it is an ordinary entry value.
		set testCount to testCount + 1
		set made to soml's fromEntries({{"opaque-pair-value", opaquePair}})
		set actualValue to item 2 of item 1 of soml's entries(made)
		if class of actualValue is not list or (actualValue as record as list) is not item caseIndex of expectedFields then
			set end of failures to "Pair validation changed opaque entry value " & caseIndex
		end if
	end repeat
	-- Existing wrong-shape and wrong-key failures retain their ordinary argument error.
	set malformedPairs to {{}, {"short"}, {"long", 7, 8}, {123, 7}, {«data utxt0031», 7}}
	repeat with caseIndex from 1 to count malformedPairs
		set suppliedEntries to {item caseIndex of malformedPairs}
		expectInvalidPair("Ordinary malformed pair " & caseIndex, suppliedEntries, 1)
		repeat with referencedEntries in {suppliedEntries}
			expectInvalidPair("Referenced malformed pair " & caseIndex, referencedEntries, 1)
		end repeat
	end repeat
end testPairValidation

on run
	set failures to {}
	set testCount to 0
	repeat with metadataClass in {integer, real, boolean, text, list, date, record, alias, application}
		set originalRecord to {class:contents of metadataClass, sample:123}
		set originalFields to originalRecord as record as list
		repeat with placement in {"direct", "array", "record"}
			set originalValue to originalRecord
			if contents of placement is "array" then
				set originalValue to {originalRecord}
			else if contents of placement is "record" then
				set originalValue to {nested:originalRecord}
			end if
			set testCount to testCount + 1
			try
				set made to soml's fromEntries({{"metadata", originalValue}})
				set actualValue to item 2 of item 1 of soml's entries(made)
				if contents of placement is "array" then
					set actualValue to item 1 of actualValue
				else if contents of placement is "record" then
					set actualValue to nested of actualValue
				end if
				if actualValue as record as list is not originalFields or sample of actualValue is not 123 then
					set end of failures to "Changed " & (metadataClass as text) & " record in " & placement
				end if
				set testCount to testCount + 1
				try
					soml's encode(made)
					set end of failures to "Encoded an opaque " & (metadataClass as text) & " record"
				on error message number errorNumber
					if errorNumber is not 2 then
						set end of failures to "Wrong error when encoding an opaque record: " & errorNumber
					end if
				end try
			on error message number errorNumber
				set end of failures to "Could not preserve " & (metadataClass as text) & " record in " & placement & ": " & errorNumber
			end try
		end repeat
		-- A record consisting only of its class field must not turn into a scalar either.
		set originalRecord to {class:contents of metadataClass}
		set originalFields to originalRecord as record as list
		set testCount to testCount + 1
		try
			set made to soml's fromEntries({{"metadata", originalRecord}})
			set actualValue to item 2 of item 1 of soml's entries(made)
			if actualValue as record as list is not originalFields then
				set end of failures to "Changed a class-only " & (metadataClass as text) & " record"
			end if
		on error message number errorNumber
			set end of failures to "Could not preserve a class-only " & (metadataClass as text) & " record: " & errorNumber
		end try
	end repeat
	-- Genuine scalar values must still produce a usable native record.
	set originalDate to current date
	repeat with scalarValue in {0, -1, 0.5, true, false, "", "a,b", originalDate}
		set testCount to testCount + 1
		set made to soml's fromEntries({{"scalar", contents of scalarValue}})
		if class of made is not record or scalar of made is not contents of scalarValue then
			set end of failures to "Changed a genuine scalar value"
		end if
	end repeat
	-- Ordinary fields that hold class constants must also retain their values.
	set originalRecord to {fieldType:record, sample:123}
	set made to soml's fromEntries({{"metadata", originalRecord}})
	set actualValue to item 2 of item 1 of soml's entries(made)
	set testCount to testCount + 1
	if fieldType of actualValue is not record or sample of actualValue is not 123 then
		set end of failures to "Changed an ordinary class-valued field"
	end if
	set previousDelimiters to AppleScript's text item delimiters
	try
		set AppleScript's text item delimiters to {",", "x"}
		set made to soml's fromEntries({{"scalar", "a,b"}, {"metadata", {class:real, sample:123}}})
		set actualPairs to soml's entries(made)
		set testCount to testCount + 1
		if item 2 of item 1 of actualPairs is not "a,b" or sample of item 2 of item 2 of actualPairs is not 123 then
			set end of failures to "Caller text item delimiters changed entry values"
		end if
	on error message number errorNumber
		set end of failures to "Caller text item delimiters broke construction: " & errorNumber
	end try
	set AppleScript's text item delimiters to previousDelimiters
	testPairValidation()
	if failures is not {} then
		error soml's joinTexts(failures, linefeed)
	end if
	return (testCount as text) & " construction regression checks passed"
end run
