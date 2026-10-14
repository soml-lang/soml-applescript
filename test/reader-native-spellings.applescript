(*
Internal helper names must not reserve capitalized spellings of ordinary configuration keys. Reading the same lower-case key inside a nested object must preserve native records too.
*)
use AppleScript version "2.8"
use soml : script "SOML"

on run
	if soml's compareCodes({97}, {98}) is not -1 or soml's sortedCodeOrder({{98}, {97}}) is not {2, 1} then
		error "Comparison helpers changed their results" number 99
	end if
	repeat with sourceText in {"sources: ['one', 'two']", "outer: {sources: ['one', 'two']}"}
		set parsed to soml's decode(contents of sourceText)
		if class of parsed is not record then
			error "An internal helper reserved a capitalized spelling of sources" number 99
		end if
		set pairs to soml's entries(parsed)
		if item 1 of item 1 of pairs is "outer" then
			set parsed to item 2 of item 1 of pairs
			if class of parsed is not record then
				error "An internal helper forced a nested sources object to be tagged" number 99
			end if
			set pairs to soml's entries(parsed)
		end if
		if soml's codePoints(item 1 of item 1 of pairs) is not {115, 111, 117, 114, 99, 101, 115} or item 2 of item 1 of pairs is not {"one", "two"} then
			error "The native sources record changed its exact entries" number 99
		end if
	end repeat
	return "Internal spelling regression checks passed"
end run
