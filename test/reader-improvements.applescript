(*
Reader stress cases combine long scalar text, bounded diagnostics, and sibling frame reuse. Expected values and diagnostic excerpts are constructed independently of the parser.
*)
use AppleScript version "2.8"
use soml : script "SOML"

on run
	set longZeros to "0"
	repeat 13 times
		set longZeros to longZeros & longZeros
	end repeat
	set groupedZeros to "0_"
	repeat 12 times
		set groupedZeros to groupedZeros & groupedZeros
	end repeat
	set parsed to soml's decode("[1." & longZeros & "e0, 1." & groupedZeros & "0e0, -0." & groupedZeros & "0e999]")
	if parsed is not {1.0, 1.0, 0.0} or class of item 1 of parsed is not real or class of item 2 of parsed is not real or class of item 3 of parsed is not real then
		error "Long float normalization changed numeric values or types" number 99
	end if
	checkInvalid("[1." & groupedZeros & "0e999]", "too large to be a finite float", 1, 2)
	checkInvalid("[1." & groupedZeros & "0e-999]", "too small to be told apart from zero", 1, 2)

	-- A large dotted key needs only a short preview of its suggested nested object.
	set dottedKey to "ab.cd"
	repeat 11 times
		set dottedKey to dottedKey & "." & dottedKey
	end repeat
	checkInvalid(dottedKey & ": 0", "as in ab: {cd: {ab: {cd: {ab: {cd: {ab: {cd: {…", 1, 3)
	checkInvalid("[1years" & longZeros & "]", "there is no year unit", 1, 2)
	checkInvalid("[1yearsyears" & longZeros & "]", "A string value must be quoted", 1, 2)

	-- Literal block contents retain indentation, apostrophes, trailing spaces, and blank lines without scanning the full content twice.
	set longContent to "prefix'" & longZeros & "  "
	set parsed to soml's decode("['''" & linefeed & "  " & longContent & linefeed & " " & linefeed & "  after" & linefeed & "  ''', 0.125]")
	if item 1 of parsed is not longContent & linefeed & linefeed & "after" or item 2 of parsed is not 0.125 then
		error "Long block content or the following float changed" number 99
	end if
	set combining to character id 769
	set parsed to soml's decode("['''" & linefeed & combining & longContent & linefeed & combining & "tail" & linefeed & "''']")
	if soml's codePoints(item 1 of parsed) is not soml's codePoints(combining & longContent & linefeed & combining & "tail") then
		error "Block scan skipped a line feed followed by a combining mark" number 99
	end if
	checkInvalid("[\"\"\"" & linefeed & "\\q" & linefeed & "  \"\"\"]", "This line does not start with the indentation", 2, 1)

	-- Siblings repeatedly reuse the same stack slots while deferred floats still point into their owning collections.
	script Store
		property parts : {}
	end script
	repeat with step from 1 to 120
		set end of Store's parts to "[" & step & ", {a:0.125,A:1.25}, [null, 1e2]]"
	end repeat
	set parsed to soml's decode("[" & soml's joinTexts(Store's parts, ",") & "]")
	repeat with step from 1 to 120
		set sibling to item step of parsed
		if item 1 of sibling is not step or class of item 2 of sibling is not SOML object or entries of item 2 of sibling is not {{"a", 0.125}, {"A", 1.25}} or item 3 of sibling is not {missing value, 100.0} then
			error "Sibling frame reuse changed values at " & step number 99
		end if
	end repeat
	return "129 reader improvement checks passed"
end run

(*
Checks a parser error's stable reason fragment and exact Unicode scalar position.
*)
on checkInvalid(sourceText, expectedReason, expectedLine, expectedColumn)
	try
		soml's decode(sourceText)
		error "Accepted invalid reader stress case" number 99
	on error message number errorNumber from details
		if errorNumber is not 1 then
			error message number errorNumber
		end if
		if reason of details does not contain expectedReason or |line| of details is not expectedLine or |column| of details is not expectedColumn then
			error "Wrong reader stress diagnostic: " & message number 99
		end if
	end try
end checkInvalid
