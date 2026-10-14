(*
Direct collection boundary regressions check every member around the reader's storage blocks and object-key budget. Depth expectations were independently verified against the JavaScript implementation, including an object leaf's additional nesting level.
*)
use AppleScript version "2.8"
use soml : script "SOML"

on run
	set memberChecks to 0
	repeat with countReference in {999, 1000, 1001, 1999, 2000, 2001, 3999, 4000, 4001}
		set memberCount to contents of countReference
		set parsed to readMembers(memberCount)
		checkRepresentation(parsed, memberCount)
		script Store
			property pairs : {}
		end script
		set Store's pairs to soml's entries(parsed)
		if (count Store's pairs) is not memberCount then
			error "Lost members at count " & memberCount
		end if
		repeat with step from 1 to memberCount
			checkMember(item step of Store's pairs, step, memberCount)
			set memberChecks to memberChecks + 1
		end repeat
	end repeat

	-- The nested a/A keys bring 3998 root keys to exactly the 4000-key budget.
	set parsed to readMembers(3998)
	checkRepresentation(parsed, 3998)
	set pairs to soml's entries(parsed)
	if (count pairs) is not 3998 then
		error "Lost members at the exact distinct-key budget"
	end if
	checkMember(item 1 of pairs, 1, 3998)
	checkMember(item 3998 of pairs, 3998, 3998)

	set depthChecks to 0
	set leaves to {"0.5", "null", "{}", "{a:1.5,A:2.5}", "'" & character id 65279 & "x'"}
	repeat with depthReference in {99, 100, 101}
		set theDepth to contents of depthReference
		repeat with leafReference in leaves
			set theLeaf to contents of leafReference
			set isObjectLeaf to theLeaf starts with "{"
			repeat with isBareReference in {false, true}
				set isBare to contents of isBareReference
				set wrapperCount to theDepth
				set prefix to ""
				if isBare then
					set wrapperCount to wrapperCount - 1
					set prefix to "a:"
				end if
				set sourceText to prefix & repeatText("[", wrapperCount) & theLeaf & repeatText("]", wrapperCount)
				set isValid to theDepth < 100 or (theDepth = 100 and not isObjectLeaf)
				set expectedColumn to 101
				if isBare then
					set expectedColumn to 102
				end if
				checkDepth(sourceText, isValid, expectedColumn, theLeaf)
				set depthChecks to depthChecks + 1
			end repeat
		end repeat
	end repeat
	return (memberChecks as text) & " member checks, 2 exact-budget member checks, and " & depthChecks & " depth checks passed"
end run

(*
Reads members with floats, nulls, exact integers, and nested objects whose two keys collide as native record labels.
*)
on readMembers(memberCount)
	script Store
		property parts : {}
	end script
	repeat with step from 1 to memberCount
		if step mod 29 = 0 then
			set theValue to "{a:1.25,A:null}"
		else if step mod 17 = 0 then
			set theValue to "0.125"
		else if step mod 13 = 0 then
			set theValue to "9223372036854775807"
		else
			set theValue to "null"
		end if
		set end of Store's parts to "shared" & step & ":" & theValue
	end repeat
	return soml's decode("{" & soml's joinTexts(Store's parts, ",") & "}")
end readMembers

(*
Checks the root representation against the total distinct keys, including the two nested keys.
*)
on checkRepresentation(parsed, memberCount)
	set expectedClass to record
	if memberCount + 2 > 4000 then
		set expectedClass to SOML object
	end if
	if class of parsed is not expectedClass then
		error "Wrong root representation at " & memberCount & " members"
	end if
end checkRepresentation

(*
Checks a member's exact key spelling, value, and AppleScript type at its expected position.
*)
on checkMember(thePair, step, memberCount)
	set locationText to (memberCount as text) & ":" & step
	if id of item 1 of thePair is not id of ("shared" & step) then
		error "Lost member key or order at " & locationText
	end if
	set theValue to item 2 of thePair
	if step mod 29 = 0 then
		if class of theValue is not SOML object then
			error "Changed nested object representation at " & locationText
		end if
		set nestedPairs to entries of theValue
		if (count nestedPairs) is not 2 or id of item 1 of item 1 of nestedPairs is not 97 or id of item 1 of item 2 of nestedPairs is not 65 or class of item 2 of item 1 of nestedPairs is not real or item 2 of item 1 of nestedPairs is not 1.25 or item 2 of item 2 of nestedPairs is not missing value then
			error "Changed nested tagged object members at " & locationText
		end if
	else if step mod 17 = 0 then
		if class of theValue is not real or theValue is not 0.125 then
			error "Changed deferred float at " & locationText
		end if
	else if step mod 13 = 0 then
		if class of theValue is not SOML int or value of theValue is not "9223372036854775807" then
			error "Changed exact integer at " & locationText
		end if
	else if theValue is not missing value then
		error "Changed null at " & locationText
	end if
end checkMember

(*
Checks the exact supported depth, over-limit error position, and canonical stability of accepted deep collections.
*)
on checkDepth(sourceText, isValid, expectedColumn, theLeaf)
	try
		set parsed to soml's decode(sourceText)
	on error message number errorNumber from details
		if isValid or errorNumber is not 1 then
			error "Unexpected deep collection failure: " & message number errorNumber
		end if
		if |line| of details is not 1 or |column| of details is not expectedColumn or reason of details does not contain "nested more than 100 levels" then
			error "Wrong depth-limit failure: " & message
		end if
		return
	end try
	if not isValid then
		error "Accepted a collection deeper than 100 levels"
	end if
	set canonical to soml's encodeCanonical(parsed)
	if soml's encodeCanonical(soml's decode(canonical)) is not canonical then
		error "Deep collection canonical round trip changed"
	end if
	if class of parsed is not list then
		set rootPairs to soml's entries(parsed)
		if (count rootPairs) is not 1 or id of item 1 of item 1 of rootPairs is not 97 then
			error "Changed a deep bare object's member"
		end if
		set parsed to item 2 of item 1 of rootPairs
	end if
	repeat while class of parsed is list
		if (count parsed) is not 1 then
			error "Changed a deep collection's item count"
		end if
		set parsed to item 1 of parsed
	end repeat
	set leafText to theLeaf
	if theLeaf = "{a:1.5,A:2.5}" then
		set leafText to "{" & linefeed & tab & tab & "A: 2.5" & linefeed & tab & tab & "a: 1.5" & linefeed & tab & "}"
	end if
	set expectedCanonical to "[" & linefeed & tab & leafText & linefeed & "]" & linefeed
	if soml's codePoints(soml's encodeCanonical({parsed})) is not soml's codePoints(expectedCanonical) then
		error "Changed a deep collection's leaf value"
	end if
	if theLeaf = "0.5" then
		if class of parsed is not real then
			error "Changed a deep float's type"
		end if
	else if theLeaf starts with "{" then
		if class of parsed is not SOML object then
			error "Changed a deep tagged object's type"
		end if
	else if theLeaf starts with "'" then
		if class of parsed is not text or id of parsed is not {65279, 120} then
			error "Changed a deep fragile string's type or code points"
		end if
	else if parsed is not missing value then
		error "Changed a deep null's type"
	end if
end checkDepth

(*
Repeats a delimiter to construct depth-boundary input without recursive test code.
*)
on repeatText(theText, theCount)
	set parts to {}
	repeat theCount times
		set end of parts to theText
	end repeat
	return soml's joinTexts(parts, "")
end repeatText
