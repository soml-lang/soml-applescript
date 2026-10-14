(*
fromEntries() preserves genuine malformed text as opaque data, including inside native lists and records. Native UTF-16 units and UTF-8 invalidity provide an independent oracle before and after construction.
*)
use AppleScript version "2.8"
use framework "Foundation"
use scripting additions
use soml : script "SOML"
property failures : {}
property checks : 0

on nativeText(theText)
	return (current application's NSString's stringWithString:("x" & theText))'s substringFromIndex:1
end nativeText

on checkUnits(theName, theText, expectedNative)
	if class of theText is not text then
		error theName & ": changed text class"
	end if
	set actualNative to nativeText(theText)
	if (actualNative's |length|()) is not (expectedNative's |length|()) then
		error theName & ": changed UTF-16 unit count"
	end if
	repeat with unitIndex from 0 to ((expectedNative's |length|()) as integer) - 1
		if (actualNative's characterAtIndex:unitIndex) is not (expectedNative's characterAtIndex:unitIndex) then
			error theName & ": changed UTF-16 unit " & unitIndex
		end if
	end repeat
	if (actualNative's dataUsingEncoding:(current application's NSUTF8StringEncoding) allowLossyConversion:false) is not missing value then
		error theName & ": lost UTF-8 invalidity"
	end if
end checkUnits

set nativeAstral to current application's NSString's stringWithString:(character id 1114111)
set nativeSurrogates to {nativeAstral's substringToIndex:1, nativeAstral's substringFromIndex:1}
set prefixes to {"", "x", character id 65279, character id 65534, "e" & (character id 769)}
set suffixes to {"", "a", character id 65534}
repeat with surrogateIndex from 1 to count nativeSurrogates
	set nativeSurrogate to item surrogateIndex of nativeSurrogates
	repeat with prefixIndex from 1 to count prefixes
		repeat with suffixIndex from 1 to count suffixes
			set expectedNative to ((nativeText(item prefixIndex of prefixes))'s stringByAppendingString:nativeSurrogate)'s stringByAppendingString:(nativeText(item suffixIndex of suffixes))
			-- Convert after a protected prefix, then remove it in AppleScript so initial FEFF/FFFE units survive the bridge.
			set protectedNative to (current application's NSString's stringWithString:"x")'s stringByAppendingString:expectedNative
			set protectedText to protectedNative as text
			set malformedText to text 2 thru -1 of protectedText
			checkUnits("Fixture", malformedText, expectedNative)
			repeat with placementIndex from 1 to 3
				set originalValue to malformedText
				if placementIndex is 2 then
					set originalValue to {malformedText}
				else if placementIndex is 3 then
					set originalValue to {child:malformedText}
				end if
				set checks to checks + 1
				set contextText to "surrogate " & surrogateIndex & ", prefix " & prefixIndex & ", suffix " & suffixIndex & ", placement " & placementIndex
				try
					set made to soml's fromEntries({{"opaque-text", originalValue}})
					set actualValue to item 2 of item 1 of soml's entries(made)
					if placementIndex is 2 then
						if class of actualValue is not list or (count actualValue) is not 1 then
							error "Changed the native list container"
						end if
						set actualValue to item 1 of actualValue
					else if placementIndex is 3 then
						if class of actualValue is not record then
							error "Changed the native record container"
						end if
						set actualValue to child of actualValue
					end if
					checkUnits(contextText, actualValue, expectedNative)
				on error message number errorNumber
					set end of failures to contextText & ": " & message & " (" & errorNumber & ")"
				end try
			end repeat
		end repeat
	end repeat
end repeat
if failures is not {} then
	error soml's joinTexts(failures, linefeed)
end if
return (checks as text) & " malformed Unicode construction checks passed"
