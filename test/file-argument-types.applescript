(*
decodeFile() accepts native text, file, and alias arguments. A singleton list containing one of them remains a list and must report the documented wrong-type error, including through a public root reference.
*)
use AppleScript version "2.8"
use framework "Foundation"
use scripting additions
use soml : script "SOML"
property failures : {}
property checks : 0

on expectWrongType(theName, theValue)
	set checks to checks + 1
	try
		soml's decodeFile(theValue)
		set end of failures to theName & ": accepted a container as a file argument"
	on error message number errorNumber
		if errorNumber is not -1703 then
			set end of failures to theName & ": expected -1703, got " & errorNumber & " " & message
		end if
	end try
end expectWrongType

on checkFile(theName, theValue)
	set checks to checks + 1
	try
		set decoded to soml's decodeFile(theValue)
		if class of decoded is not list or (count decoded) is not 1 or class of item 1 of decoded is not integer or item 1 of decoded is not 123 then
			set end of failures to theName & ": changed file values or their classes"
		end if
	on error message number errorNumber
		set end of failures to theName & ": " & errorNumber & " " & message
	end try
end checkFile

on expectReadError(theName, theValue)
	set checks to checks + 1
	try
		soml's decodeFile(theValue)
		set end of failures to theName & ": read a missing file"
	on error message number errorNumber
		if errorNumber is not -43 or message does not start with "Could not read the file " then
			set end of failures to theName & ": expected the documented read error, got " & errorNumber & " " & message
		end if
	end try
end expectReadError

on runChecks(fixturePath)
	set written to (current application's NSString's stringWithString:"[123]")'s writeToFile:fixturePath atomically:true encoding:(current application's NSUTF8StringEncoding) |error|:(missing value)
	if not written then
		error "Could not create the real file fixture"
	end if
	set fixtureFile to POSIX file fixturePath
	set fixtureAlias to fixtureFile as alias
	set hfsFile to (file (fixtureAlias as text)) as «class furl»
	if class of hfsFile is not «class furl» or POSIX path of hfsFile is not fixturePath then
		error "HFS fixture did not produce the expected native file"
	end if
	set nativeArguments to {fixturePath, fixtureFile, fixtureAlias, hfsFile}
	repeat with step from 1 to count nativeArguments
		set directArgument to item step of nativeArguments
		checkFile("Native file argument " & step & " direct", directArgument)
		repeat with referencedArgument in {directArgument}
			checkFile("Native file argument " & step & " reference", referencedArgument)
		end repeat
	end repeat
	set invalidLists to {{fixturePath}, {{fixturePath}}, {fixtureFile}, {fixtureAlias}}
	repeat with step from 1 to count invalidLists
		set directArgument to item step of invalidLists
		if class of directArgument is not list then
			error "Container fixture lost its native list class"
		end if
		expectWrongType("Native list argument " & step & " direct", directArgument)
		repeat with referencedArgument in {directArgument}
			expectWrongType("Native list argument " & step & " reference", referencedArgument)
		end repeat
	end repeat
	-- A path-shaped ordinary record is still data, rather than a native file argument.
	set invalidRecords to {{POSIX path:fixturePath}, {contents:fixtureFile}}
	repeat with step from 1 to count invalidRecords
		set directArgument to item step of invalidRecords
		if class of directArgument is not record then
			error "Record fixture lost its native record class"
		end if
		expectWrongType("Native record argument " & step & " direct", directArgument)
		repeat with referencedArgument in {directArgument}
			expectWrongType("Native record argument " & step & " reference", referencedArgument)
		end repeat
	end repeat
	-- A missing file remains a valid argument and reports a read error, including an alias created before deletion.
	set removed to (current application's NSFileManager's defaultManager())'s removeItemAtPath:fixturePath |error|:(missing value)
	if not removed then
		error "Could not delete the missing-file fixture"
	end if
	set missingArguments to {fixturePath, fixtureFile, fixtureAlias}
	repeat with step from 1 to count missingArguments
		set directArgument to item step of missingArguments
		expectReadError("Missing native file " & step & " direct", directArgument)
		repeat with referencedArgument in {directArgument}
			expectReadError("Missing native file " & step & " reference", referencedArgument)
		end repeat
	end repeat
end runChecks

set fixturePath to (POSIX path of (path to temporary items)) & "soml-applescript-file-argument-" & ((current application's NSUUID's UUID()'s UUIDString()) as text) & ".soml"
try
	runChecks(fixturePath)
on error message number errorNumber
	(current application's NSFileManager's defaultManager())'s removeItemAtPath:fixturePath |error|:(missing value)
	error message number errorNumber
end try
(current application's NSFileManager's defaultManager())'s removeItemAtPath:fixturePath |error|:(missing value)
if failures is not {} then
	error soml's joinTexts(failures, linefeed)
end if
return (checks as text) & " file argument type checks passed"
