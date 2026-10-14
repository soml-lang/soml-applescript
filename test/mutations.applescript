(*
Edits to native records must retain nested values, exact key spellings, and member order across construction and both writer modes.
*)
use AppleScript version "2.8"
use scripting additions
use soml : script "SOML"

property testCount : 0

on check(theName, actual, expected)
	set testCount to testCount + 1
	considering case, diacriticals, hyphens, punctuation and white space
		if actual is not expected then
			error theName & " failed" number 99
		end if
	end considering
end check

on run
	set testCount to 0
	testDecodedMutations()
	testConstructedMutations()
	testSpellingSequences()
	return (testCount as text) & " mutation checks passed"
end run

on testDecodedMutations()
	set nativeDate to soml's toDate({class:SOML instant, value:"2026-10-14T12:00:00Z"})
	set configuration to soml's decode("z-key: 0" & linefeed & "outer-list: [{Header-Name: 0.5}, {'header-name': 1.5}]" & linefeed & "empty: []")
	check("decoded root is editable", class of configuration, record)
	set originalText to soml's encode(configuration)
	set originalPairs to soml's entries(configuration)
	soml's encodeCanonical(configuration)
	check("canonical writing preserves decoded member order", soml's entries(configuration), originalPairs)
	check("canonical writing preserves decoded values", id of soml's encode(configuration), id of originalText)
	set |z-key| of configuration to {{stage:"changed"}, 0.125, nativeDate}
	set |Header-Name| of item 1 of |outer-list| of configuration to {"replacement", {value:2.5}}
	set |empty| of configuration to {false, missing value, 1}
	set configuration to configuration & {|new-list|:{3.5, {child:nativeDate}}}
	set expectedText to "z-key: [
	{
		stage: 'changed'
	}
	0.125
	2026-10-14T12:00:00Z
]
outer-list: [
	{
		Header-Name: [
			'replacement'
			{
				value: 2.5
			}
		]
	}
	{
		header-name: 1.5
	}
]
empty: [
	false
	null
	1
]
new-list: [
	3.5
	{
		child: 2026-10-14T12:00:00Z
	}
]
"
	check("decoded mutation output", id of soml's encode(configuration), id of expectedText)
	set currentPairs to soml's entries(configuration)
	check("mutated member order", {item 1 of item 1 of currentPairs, item 1 of item 2 of currentPairs, item 1 of item 3 of currentPairs, item 1 of item 4 of currentPairs}, {"z-key", "outer-list", "empty", "new-list"})
	set canonicalText to soml's encodeCanonical(configuration)
	check("canonical writing preserves edited output", id of soml's encode(configuration), id of expectedText)
	check("edited canonical round trip", id of soml's encodeCanonical(soml's decode(canonicalText)), id of canonicalText)
	check("reconstructing edited entries preserves output", id of soml's encode(soml's fromEntries(currentPairs)), id of expectedText)
end testDecodedMutations

on testConstructedMutations()
	set nativeDate to soml's toDate({class:SOML instant, value:"2026-10-14T12:00:00Z"})
	set original to soml's fromEntries({{"Sort-Z", 0.5}, {"Sort-A", {}}, {"sort-middle", {child:1}}})
	check("constructed root is editable", class of original, record)
	set |Sort-Z| of original to {1.5, {child:nativeDate}}
	set |Sort-A| of original to {"one", "two"}
	set child of |sort-middle| of original to -2.5
	set edited to original & {|tail-value|:nativeDate}
	set expectedNormal to "Sort-Z: [
	1.5
	{
		child: 2026-10-14T12:00:00Z
	}
]
Sort-A: [
	'one'
	'two'
]
sort-middle: {
	child: -2.5
}
tail-value: 2026-10-14T12:00:00Z
"
	set expectedCanonical to "Sort-A: [
	'one'
	'two'
]
Sort-Z: [
	1.5
	{
		child: 2026-10-14T12:00:00Z
	}
]
sort-middle: {
	child: -2.5
}
tail-value: 2026-10-14T12:00:00Z
"
	check("constructed mutation output", id of soml's encode(edited), id of expectedNormal)
	check("constructed mutation canonical output", id of soml's encodeCanonical(edited), id of expectedCanonical)
	check("canonical writing preserves constructed member order", id of soml's encode(edited), id of expectedNormal)
	check("reconstructing constructed entries preserves output", id of soml's encode(soml's fromEntries(soml's entries(edited))), id of expectedNormal)
end testConstructedMutations

on testSpellingSequences()
	-- Each first spelling is fresh, so later calls must preserve the previously created native record while tagging its case variants.
	repeat with step from 1 to 60
		set initialKey to "Mutation" & "-Sequence-" & step
		set otherKey to "MUTATION" & "-SEQUENCE-" & step
		set originalPairs to {{initialKey, {1.25, {nested:contents of step}}}}
		set originalRecord to soml's fromEntries(originalPairs)
		check("fresh first spelling is native", class of originalRecord, record)
		set originalText to soml's encode(originalRecord)
		set changedRecord to soml's fromEntries({{otherKey, {2.5, contents of step}}})
		check("later constructed spelling is tagged", class of changedRecord, SOML object)
		check("later constructed spelling survives", soml's entries(changedRecord), {{otherKey, {2.5, contents of step}}})
		set parsedOther to soml's decode(otherKey & ": [3.5," & step & "]")
		check("later parsed spelling is tagged", class of parsedOther, SOML object)
		check("later parsed spelling survives", soml's entries(parsedOther), {{otherKey, {3.5, contents of step}}})
		set parsedOriginal to soml's decode(initialKey & ": [4.5," & step & "]")
		check("original spelling remains native", class of parsedOriginal, record)
		check("original parsed spelling survives", soml's entries(parsedOriginal), {{initialKey, {4.5, contents of step}}})
		soml's encodeCanonical(changedRecord)
		soml's encodeCanonical(parsedOther)
		check("later calls preserve original keys and values", soml's entries(originalRecord), originalPairs)
		check("later calls preserve original output", id of soml's encode(originalRecord), id of originalText)
		set colliding to soml's fromEntries({{otherKey, 1.0}, {initialKey, 2.0}})
		check("case collisions retain caller order", soml's entries(colliding), {{otherKey, 1.0}, {initialKey, 2.0}})
		check("canonical collision sort keeps value associations", id of soml's encodeCanonical(colliding), id of (otherKey & ": 1.0" & linefeed & initialKey & ": 2.0" & linefeed))
	end repeat
end testSpellingSequences
