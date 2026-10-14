(*
Native scalar arguments must be actual text or integers. A physical record can claim either class while remaining an opaque record that fromEntries() preserves.
*)
use AppleScript version "2.8"
use scripting additions
use soml : script "SOML"
property failures : {}
property checks : 0

on check(theName, condition)
	set checks to checks + 1
	if not condition then
		set end of failures to theName
	end if
end check

on expectWrongType(theName, operation, theValue)
	set checks to checks + 1
	try
		if operation is "decode" then
			soml's decode(theValue)
		else if operation is "file" then
			soml's decodeFile(theValue)
		else if operation is "key" then
			soml's fromEntries({{contents of theValue, 7}})
		else
			soml's toNumber(theValue)
		end if
		set end of failures to theName & ": accepted an opaque record as a scalar"
	on error message number errorNumber
		if errorNumber is not -1703 then
			set end of failures to theName & ": expected -1703, got " & errorNumber & " " & message
		end if
	end try
end expectWrongType

set opaqueRecords to {{class:text}, {class:text, sample:123}, {sample:123, class:text}, {class:integer}, {class:integer, sample:123}, {sample:123, class:integer}}
set expectedFields to {{text}, {text, 123}, {123, text}, {integer}, {integer, 123}, {123, integer}}
repeat with step from 1 to count opaqueRecords
	set originalValue to item step of opaqueRecords
	set restoredValue to item 2 of item 1 of soml's entries(soml's fromEntries({{"opaque", originalValue}}))
	check("Opaque record " & step & " changed class during construction", class of restoredValue is class of originalValue)
	check("Opaque record " & step & " changed physical fields during construction", (restoredValue as record as list) is item step of expectedFields)
	set arguments to {originalValue, restoredValue}
	if step ≤ 3 then
		set operations to {"decode", "file", "key"}
	else
		set operations to {"number"}
	end if
	repeat with argumentIndex from 1 to count arguments
		set directValue to item argumentIndex of arguments
		repeat with operation in operations
			set operation to contents of operation
			set context to "Opaque record " & step & ", argument " & argumentIndex & ", " & operation
			expectWrongType(context & " direct", operation, directValue)
			-- A loop variable is a genuine reference to the physical record, not its contents.
			repeat with referencedValue in {directValue}
				expectWrongType(context & " loop reference", operation, referencedValue)
			end repeat
		end repeat
	end repeat
end repeat

-- Genuine text keys retain exact spelling, including the two prefixes that Foundation's text bridge changes.
set genuineKeys to {"", "actual-key", "é🦄", character id 65279, character id 65534, (character id 65279) & (character id 65534) & "key"}
repeat with keyIndex from 1 to count genuineKeys
	set directKey to item keyIndex of genuineKeys
	set restoredPair to item 1 of soml's entries(soml's fromEntries({{directKey, 7}}))
	check("Direct genuine key " & keyIndex & " changed class or spelling", class of item 1 of restoredPair is text and id of item 1 of restoredPair is id of directKey)
	check("Direct genuine key " & keyIndex & " changed its value", item 2 of restoredPair is 7)
	repeat with referencedKey in {directKey}
		set keyPairs to {{contents of referencedKey, 7}}
		repeat with referencedPairs in {keyPairs}
			set restoredPair to item 1 of soml's entries(soml's fromEntries(referencedPairs))
			check("Referenced genuine key " & keyIndex & " changed class or spelling", class of item 1 of restoredPair is text and id of item 1 of restoredPair is id of directKey)
			check("Referenced genuine key " & keyIndex & " changed its value", item 2 of restoredPair is 7)
		end repeat
	end repeat
end repeat

-- Text documents with ordinary and leading FEFF/FFFE string values remain supported.
set genuineTexts to {"actual text", (character id 65279) & "text", (character id 65534) & "text"}
repeat with textIndex from 1 to count genuineTexts
	set expectedText to item textIndex of genuineTexts
	set documentText to "actual: '" & expectedText & "'"
	set actualText to item 2 of item 1 of soml's entries(soml's decode(documentText))
	check("Direct genuine document " & textIndex & " changed its text value", class of actualText is text and id of actualText is id of expectedText)
	repeat with referencedDocument in {documentText}
		set actualText to item 2 of item 1 of soml's entries(soml's decode(referencedDocument))
		check("Referenced genuine document " & textIndex & " changed its text value", class of actualText is text and id of actualText is id of expectedText)
	end repeat
end repeat

set genuineIntegers to {-536870911 - 1, 0, 536870911 + 1}
repeat with integerIndex from 1 to count genuineIntegers
	set expectedInteger to item integerIndex of genuineIntegers
	set actualInteger to soml's toNumber(expectedInteger)
	check("Direct genuine integer " & integerIndex & " changed class or value", class of actualInteger is integer and actualInteger is expectedInteger)
	repeat with referencedInteger in {expectedInteger}
		set actualInteger to soml's toNumber(referencedInteger)
		check("Referenced genuine integer " & integerIndex & " changed class or value", class of actualInteger is integer and actualInteger is expectedInteger)
	end repeat
end repeat

if failures is not {} then
	error soml's joinTexts(failures, linefeed)
end if
return (checks as text) & " native scalar argument checks passed"
