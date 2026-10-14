(*
Reader regressions for float errors discovered before the collection receives the value.
*)
use AppleScript version "2.8"
use soml : script "SOML"

on run
	set cases to {{"[1.0\\]", 1, 5, "Unexpected"}, {"a:1e2\\", 1, 6, "Unexpected"}, {"{a:1e2?}", 1, 7, "Unexpected"}, {"[0.0\\]", 1, 5, "Unexpected"}, {"[1e2" & character id 8203 & "]", 1, 5, "Unexpected"}, {"[1.0:2]", 1, 2, "Invalid number"}, {"{a:0,a:1.0}", 1, 6, "Duplicate key"}, {"a:0" & linefeed & "a:1.0", 2, 1, "Duplicate key"}, {"[0.5,[1.0\\]]", 1, 10, "Unexpected"}, {"{a:1.0,b:1e2\\}", 1, 13, "Unexpected"}, {"[1e999\\]", 1, 2, "too large"}, {"a:1e-999\\", 1, 3, "too small"}, {"[0.5,1e999\\]", 1, 6, "too large"}, {"{a:0.5,b:1e-999\\}", 1, 10, "too small"}, {"{a:0,a:1e999}", 1, 8, "too large"}, {"{a:0,a:1e-999}", 1, 8, "too small"}}
	set failures to {}
	repeat with theCase in cases
		set failure to checkFailure(contents of theCase)
		if failure is not missing value then
			set end of failures to failure
		end if
	end repeat
	if failures is not {} then
		error soml's joinTexts(failures, linefeed) number 99
	end if

	-- A failed reading must not affect later float conversion or collection slots.
	set parsed to soml's decode("{a:0.5,b:[1e2,1.25,{c:-2.5}]}")
	if a of parsed is not 0.5 or item 1 of b of parsed is not 100.0 or item 2 of b of parsed is not 1.25 or c of item 3 of b of parsed is not -2.5 then
		error "Float values changed after invalid documents" number 99
	end if
	set parsed to soml's decode("[0.0,1e2,1e-2,-1.5]")
	if parsed is not {0.0, 100.0, 0.01, -1.5} then
		error "Valid array float values changed" number 99
	end if
	return "18 reader regression checks passed"
end run

on checkFailure(theCase)
	set {sourceText, expectedLine, expectedColumn, expectedReason} to theCase
	try
		soml's decode(sourceText)
		return "Accepted invalid float input " & sourceText
	on error message number errorNumber from details
		if errorNumber is not 1 then
			return "Expected SOML error 1 for " & sourceText & ", got " & errorNumber & ": " & message
		end if
		if |line| of details is not expectedLine or |column| of details is not expectedColumn then
			return "Wrong error location for " & sourceText & ": " & message
		end if
		if reason of details does not contain expectedReason then
			return "Wrong error reason for " & sourceText & ": " & message
		end if
	end try
	return missing value
end checkFailure
