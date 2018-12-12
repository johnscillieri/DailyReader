{.experimental: "codeReordering".}

## ToDo
## Fix bad shell characters
## Maybe move "The" to the end

import os
import osproc
import sequtils
import strformat
import strutils
import times

import commandeer

template get_filename: string = instantiationInfo().filename.splitFile()[1]
const app_name = get_filename()

const version = &"{app_name} 0.5b"

const usage_text = &"""

Usage:
    {app_name} <book> [--dry-run]
    {app_name} (-h | --help)
    {app_name} (-v | --version)

  Options:
    -d --dry-run                Output new title but don't actually rename book
    -h --help                   Show this screen.
    -v --version                Show version.
"""

const full_help_text = &"""
{version}

Renames a given book using the ebook-meta tool from Calibre

Uses the format: <TITLE> - <AUTHOR> - <YEAR>.ext
{usage_text}
"""

proc main() =
    commandline:
        argument book, string
        option dry_run, bool, "dry-run", "d"
        exitoption "help", "h", full_help_text
        exitoption "version", "v", version
        errormsg usage_text

    let (dir, old_name, ext) = splitFile(book)

    let new_title = create_new_base_name( execProcess( &"ebook-meta \"{book}\"" ) )
    let new_name = dir / new_title.addFileExt( ext )

    echo( &"Renaming: {book}" )
    echo( &"To      : {new_name}" )

    if not dry_run:
        moveFile( book, new_name )

    echo( "Done!" )


template between( source, start_token, end_token: string ): string =
    let first_parts = source.split( start_token )
    if len( first_parts ) <= 1:
        ""
    else:
        first_parts[1].split( end_token )[0].strip()


proc create_new_base_name( ebook_meta_output: string ): string =
    let title = ebook_meta_output.between( "Title               : ", "\n" )
    result = title

    let author = ebook_meta_output.between( "Author(s)           : ", "[" ).split( "\n" )[0]
    if author != "":
        result &= " - " & author

    let year = ebook_meta_output.between( "Published           : ", "-" ).split( "\n" )[0]
    if year != "":
        result &= " - " & year


when isMainModule:
    main()
