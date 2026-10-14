(*
Deferred real and date lines that begin immediately after a full 4,000-piece output block must retain their complete prefixes and line endings. Both orders exercise each deferred-value queue at the boundary.
*)
use AppleScript version "2.8"
use framework "Foundation"
use soml : script "SOML"

on run
	set nativeDate to (current application's NSDate's dateWithTimeIntervalSince1970:-1) as date
	script Store
		property values : {}
		property expectedPieces : {"["}
	end script
	repeat with step from 1 to 3999
		set end of Store's values to contents of step
		set end of Store's expectedPieces to tab & step
	end repeat
	repeat with pendingOrder in {{0.125, nativeDate}, {nativeDate, 0.125}}
		set pendingOrder to contents of pendingOrder
		set fixture to (Store's values) & pendingOrder & {"after"}
		set expectedLines to Store's expectedPieces
		if class of item 1 of pendingOrder is real then
			set expectedLines to expectedLines & {tab & "0.125", tab & "1969-12-31T23:59:59Z"}
		else
			set expectedLines to expectedLines & {tab & "1969-12-31T23:59:59Z", tab & "0.125"}
		end if
		set expectedLines to expectedLines & {tab & "'after'", "]", ""}
		set nativeExpected to current application's NSString's stringWithString:(soml's joinTexts(expectedLines, linefeed))
		repeat with isCanonical in {false, true}
			if contents of isCanonical then
				set actual to soml's encodeCanonical(fixture)
			else
				set actual to soml's encode(fixture)
			end if
			if not (nativeExpected's isEqualToString:actual) as boolean then
				error "A deferred line changed at an output block boundary" number 99
			end if
		end repeat
	end repeat
	return "4 deferred line boundary checks passed"
end run
