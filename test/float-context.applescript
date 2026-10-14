(*
Reading and writing share numeric conversion functions without retaining a failed operation's values or formatting rules.
*)
use AppleScript version "2.8"
use framework "JavaScriptCore"
use scripting additions
use soml : script "SOML"

property checks : 0

on check(theName, actual, expected)
	set checks to checks + 1
	if actual is not expected then
		error theName & " failed" number 99
	end if
end check

on run
	set checks to 0
	set context to current application's JSContext's new()
	set notANumber to ((context's evaluateScript:"NaN")'s toDouble()) as real
	set sourceText to "[0.125, -0.0, 1e100, 5e-324, infinity, -infinity]"
	set expectedText to "[" & linefeed & tab & "0.125" & linefeed & tab & "0.0" & linefeed & tab & "1e100" & linefeed & tab & "5e-324" & linefeed & tab & "infinity" & linefeed & tab & "-infinity" & linefeed & "]" & linefeed
	repeat 10 times
		set decoded to soml's decode(sourceText)
		check("reading preserves a finite real", item 1 of decoded, 0.125)
		check("reading keeps float classification", class of item 2 of decoded, real)
		check("writing keeps exact scalar spellings", id of soml's encode(decoded), id of expectedText)
		try
			soml's decode("[1e999]")
			error "Accepted an overflowing float" number 99
		on error message number errorNumber
			check("overflow remains an input error", errorNumber, 1)
			check("overflow reason remains specific", message contains "too large to be a finite float", true)
		end try
		try
			soml's encode({notANumber})
			error "Encoded NaN" number 99
		on error message number errorNumber
			check("NaN remains a writer error", errorNumber, 2)
			check("NaN keeps its array path", message contains "at [0]", true)
		end try
		check("formatting works after a writer failure", id of soml's encodeCanonical(soml's decode("[1_000.25, -2e-3]")), id of ("[" & linefeed & tab & "1000.25" & linefeed & tab & "-0.002" & linefeed & "]" & linefeed))
		check("infinities survive alternating conversion functions", id of soml's encode(soml's decode(sourceText)), id of expectedText)
	end repeat
	return (checks as text) & " numeric conversion context checks passed"
end run
