use AppleScript version "2.8"
use scripting additions
use soml : script "SOML"

on run
	set failures to {}
	set dangerousText to (character id 27) & "[31m" & (character id 8238)
	try
		soml's encode({class:SOML object, entries:{{dangerousText, me}}})
		set end of failures to "Unsupported values must fail"
	on error message number errorNumber
		if errorNumber is not 2 or (id of message) contains 27 or (id of message) contains 8238 then
			set end of failures to "Writer errors must escape terminal and direction controls"
		end if
	end try
	try
		soml's encode({class:SOML object, entries:{{dangerousText, return}}})
		set end of failures to "Carriage returns must fail"
	on error message number errorNumber
		if errorNumber is not 2 or (id of message) contains 27 or (id of message) contains 8238 then
			set end of failures to "String validation errors must escape controls in their paths"
		end if
	end try
	try
		soml's encode({class:SOML object, entries:{{dangerousText & return, 1}}})
		set end of failures to "Carriage returns in keys must fail"
	on error message number errorNumber
		if errorNumber is not 2 or (id of message) contains 27 or (id of message) contains 8238 then
			set end of failures to "Key validation errors must escape terminal and direction controls"
		end if
	end try

	set hugeText to "invalid"
	repeat 12 times
		set hugeText to hugeText & hugeText
	end repeat
	try
		soml's encode({a:{class:SOML int, value:hugeText}})
		set end of failures to "Invalid tagged integers must fail"
	on error message number errorNumber
		if errorNumber is not 2 or (length of message) > 250 then
			set end of failures to "Tagged integer diagnostics must be bounded"
		end if
	end try
	try
		soml's encode({a:{class:SOML instant, value:dangerousText}})
		set end of failures to "Invalid tagged instants must fail"
	on error message number errorNumber
		if errorNumber is not 2 or (id of message) contains 27 or (id of message) contains 8238 then
			set end of failures to "Tagged instant diagnostics must escape controls"
		end if
	end try

	-- A lone surrogate cannot be spelled in AppleScript source, so it comes from the shell's tolerant read of invalid UTF-8. `id of` merges it with the character after it, so the writer must not trust the codes alone.
	try
		soml's encode({|k|:(do shell script "printf '\\xed\\xa0\\x80A'")})
		set end of failures to "A lone surrogate in a string must fail"
	on error message number errorNumber
		if errorNumber is not 2 or message does not contain "lone surrogate" then
			set end of failures to "A lone surrogate in a string must name itself"
		end if
	end try
	try
		soml's encode({class:SOML object, entries:{{(do shell script "printf '\\xed\\xa0\\x80key'"), 1}}})
		set end of failures to "A lone surrogate in a key must fail"
	on error message number errorNumber
		if errorNumber is not 2 or message does not contain "lone surrogate" then
			set end of failures to "A lone surrogate in a key must name itself"
		end if
	end try
	set longSurrogateText to do shell script "printf '\\xed\\xa0\\x80'"
	repeat 100 times
		set longSurrogateText to longSurrogateText & "aaaaaaaaaa"
	end repeat
	try
		soml's encode({|k|:longSurrogateText})
		set end of failures to "A lone surrogate in a long string must fail"
	on error message number errorNumber
		if errorNumber is not 2 or message does not contain "lone surrogate" then
			set end of failures to "A lone surrogate in a long string must name itself"
		end if
	end try
	if failures is not {} then
		error failures as text
	end if
	return "8 writer security tests passed"
end run
