{.experimental: "codeReordering".}

import base64
import httpclient
import math
import os
import sequtils
import strformat
import strutils
import times

import commandeer
import parsetoml

template get_filename: string = instantiationInfo().filename.splitFile()[1]
const app_name = get_filename()

const version = &"{app_name} 1.0"

const usage_text = &"""

Usage:
    {app_name} run [options]
    {app_name} add <book> [--position <index>] [options]
    {app_name} list
    {app_name} remove <position>
    {app_name} (-h | --help)
    {app_name} (-v | --version)

Options:
    -f --from=<address>             Email address to send from
    -t --to=<address>               Email address to send to
    -U --mailgun-url=<url>          Mailgun API URL
    -K --mailgun-key=<key>          Mailgun API Key
    -s --start=<page num>           Page number to start from
    -n --new-pages=<number>         Number of new pages to send
    -F --force                      Override the 20 page max safety check
    -E --ebook-convert-args=<args>  String of arguments to pass to ebook-convert
    -P --pdftoppm-args=<args>       String of arguments to pass to pdftoppm
    -N --no-send                    Don't send the email or update the start

    -h --help                       Show this screen.
    -v --version                    Show version.
"""

const full_help_text = &"""
{version}

Automates emailing pages from a book, keeping track of where you left off.

Useful as a cron job to create a regular reading habit.

Converts the book to a PDF for a stable rendering, then splits the pages of the
PDF into individual PNGs to include inline in an email.

{app_name} should support any format Calibre does (epub, mobi, pdf, etc).

The --new-pages argument is the number of NEW pages to send. The last page of
the prior batch is included as the first page of the next email so the reader
can maintain context. For example, if --new-pages is set to 5, and your last
batch was pages 5-10, the next email that gets sent will be six pages long,
pages 10-15, inclusive.

If you'd like to just update your settings without sending an email (and
changing the start page), use the --no-send flag. Also useful for debugging.
{usage_text}
"""

const ebook_convert_args_default = "--pdf-page-margin-bottom=36 --pdf-page-margin-top=18 --pdf-page-numbers --pdf-default-font-size=24"
const pdftoppm_args_default = "-f 1 -l 0"
const default_config = """
[email]
from = ""
to = ""
[email.mailgun]
api_url = ""
api_key = ""
"""

proc main() =
    commandline:
        subcommand run, "run":
            option no_send, bool, "no-send", "N"
            option force, bool, "force", "F"
        subcommand add, "add":
            argument book, string
            option add_position, Natural, "position", "p", 0
        subcommand list, "list":
            discard
        subcommand remove, "remove":
            argument remove_position, Natural
        option config_file_arg, string, "config", "c"
        option start_arg, int, "start", "s"
        option new_pages_arg, int, "new-pages", "n"
        option from_arg, string, "from", "f"
        option to_arg, string, "to", "t"
        option mailgun_url_arg, string, "mailgun-url", "U"
        option mailgun_key_arg, string, "mailgun-key", "K"
        option ebook_convert_args_cmdline, string, "ebook-convert-args", "E"
        option pdftoppm_args_cmdline, string, "pdftoppm-args", "P"
        exitoption "help", "h", full_help_text
        exitoption "version", "v", version
        errormsg usage_text

    let config_dir = os.getConfigDir() / app_name
    createDir(config_dir)

    let cache_dir = get_cache_dir(app_name)
    createDir(cache_dir)

    let config_file_path = if config_file_arg != "": config_file_arg
                           else: config_dir / "config.toml"
    var config = if existsFile(config_file_path): parseFile(config_file_path)
                 else: parseString(default_config)

    if from_arg != "": config{"email", "from"} = ?from_arg
    if config{"email", "from"}.getStr("") == "":
        quit("ERROR: Missing required 'from' argument/config value. Exiting.")

    if to_arg != "": config{"email", "to"} = ?to_arg
    if config{"email", "to"}.getStr("") == "":
        quit("ERROR: Missing required 'to' argument/config value. Exiting.")

    if mailgun_url_arg != "": config{"email", "mailgun", "api_url"} = ?mailgun_url_arg
    if config{"email", "mailgun", "api_url"}.getStr("") == "":
        quit("ERROR: Missing required 'Mailgun API URL' argument/config value. Exiting.")

    if mailgun_key_arg != "": config{"email", "mailgun", "api_key"} = ?mailgun_key_arg
    if config{"email", "mailgun", "api_key"}.getStr("") == "":
        quit("ERROR: Missing required 'Mailgun API Key' argument/config value. Exiting.")

    if ebook_convert_args_cmdline != "": config{"general", "ebook_convert_args"} = ?ebook_convert_args_cmdline
    if config{"general", "ebook_convert_args"}.getStr() == "": config{"general", "ebook_convert_args"} = ?ebook_convert_args_default

    if pdftoppm_args_cmdline != "": config{"general", "pdftoppm_args"} = ?pdftoppm_args_cmdline
    if config{"general", "pdftoppm_args"}.getStr() == "": config{"general", "pdftoppm_args"} = ?pdftoppm_args_default

    if run:
        config.run(force)
        # TODO - if a book is finished, it should add it to a finished list

    elif add:
        config.add_book(book, add_position)

    elif list:
        config.list_books()

    elif remove:
        config.remove_book(remove_position)

    else:
        quit(usage_text)

    writeFile(config_file_path, config.toTomlString())

    echo("\nDone!")


proc get_cache_dir(app_name: string): string =
    ## Read the path to the user's temporary cache directory
    result = getEnv("XDG_CACHE_HOME")
    if result != "":
        return result / app_name

    if existsEnv("HOME") == false:
        echo("WARNING: Couldn't read $XDG_CACHE_HOME or $HOME. Using the current application directory as the cache file location.")
        return getAppDir()

    return getEnv("HOME") / ".cache" / app_name


proc run(config: TomlValueRef, force: bool) =

    if not config.hasKey("books"):
        quit("Couldn't run with no books. Add a book first and try again. Exiting.")

    let book = config["books"].getElems()[0].getTable()
    let book_base_name = book["name"].getStr()

    let pages_folder = get_cache_dir(app_name) / &"{book_base_name}_pages"
    let total_pages = len(toSeq(walkFiles(&"{pages_folder}/*.png")))
    if total_pages == 0:
        quit(&"ERROR: No pages were found in {pages_folder}. Exiting.")

    let start = if book.hasKey("start"): book["start"].getInt() else: 1
    let new_pages = if book.hasKey("new_pages"): book["new_pages"].getInt()
                    else: num_pages_to_send(current_page = start, total_pages = total_pages)

    let percent = int((start + new_pages - 1) / total_pages * 100)
    let subject = &"DailyReader: {book_base_name} - page {start}-{start+new_pages-1} of {total_pages} ({percent}%)"
    echo(subject)

    # TODO - make this a setting in the config file
    if new_pages > 20 and force == false:
        quit("ERROR: Attempting to send more than 20 pages without the force flag.")

    var files_to_attach: seq[string] = @[]
    # start-1 so that you send the last previously read page for context
    for i in (start-1)..<(start+new_pages):
        let current_page = absolutePath(pages_folder / &"page-{i:03}.png")
        if not os.fileExists(current_page): continue
        files_to_attach.add(current_page)
        echo(&"Added {current_page}...")

    let multipart_message = create_message(config{"email", "from"}.getStr(),
                                           config{"email", "to"}.getStr(),
                                           subject,
                                           files_to_attach)
    send_message_mailgun(multipart_message,
                         config{"email", "mailgun", "api_key"}.getStr(""),
                         config{"email", "mailgun", "api_url"}.getStr(""))

    book["start"] = ?(start+new_pages)

    # TODO - needs to set the new_pages config appropriately
    # Set the config value for book.new_pages IFF the user set it
    # if new_pages_arg != 0 or config{"books", book_base_name, "new_pages"}.getInt(0) != 0:
    #     config{"books", book_base_name, "new_pages"} = ?new_pages


proc add_book(config: TomlValueRef, book: string, position: Natural) =
    echo(&"Adding book {book}...\n")

    let cache_dir = get_cache_dir(app_name)
    let ebook_convert_args = config{"general", "ebook_convert_args"}.getStr()
    let path_to_pdf = create_pdf(book, cache_dir, ebook_convert_args)

    let pdftoppm_args = config{"general", "pdftoppm_args"}.getStr()
    let pages_folder = create_png_pages(path_to_pdf, pdftoppm_args)

    let base_name = changeFileExt(extractFilename(book), "")

    if not config.hasKey("books"):
        config{"books"} = ?*[{ "name": base_name, "start": 1 }]

    var current_list = config["books"].getElems()

    let to_insert = ?*{ "name": base_name, "start": 1 }
    if position == 0 or position > current_list.high:
        current_list.add(to_insert)
    else:
        current_list.insert(to_insert, position-1)

    config["books"] = ?current_list

    echo("Added successfully.\n")
    config.list_books()


proc list_books( config: TomlValueRef ) =
    echo("Listing books...\n")

    if not config.hasKey("books"):
        echo("No books found. Add one using the 'add' command.")
        return

    let books = config["books"].getElems()
    for i, book in books:
        echo( &"{i+1:03d} - {book[\"name\"].getStr()}")


proc remove_book(config: TomlValueRef, position: Natural) =
    echo(&"Removing book at position {position}...\n")

    if not config.hasKey("books"):
        echo("No books found in list.")
        return

    var current_list = config["books"].getElems()

    if position == 0 or position > len(current_list):
        echo("Invalid position to remove. Check your number and try again.\n")
        config.list_books()
        return

    let to_remove = current_list[position-1]
    echo(&"Removing {to_remove[\"name\"]}...")
    current_list.delete(position-1)
    config["books"] = ?current_list

    let cache_dir = get_cache_dir(app_name)

    let pdf_file = cache_dir / &"{to_remove[\"name\"]}.pdf"
    removeFile(pdf_file)

    let pages_folder = cache_dir / &"{to_remove[\"name\"]}_pages"
    removeDir(pages_folder)

    echo("Removed successfully.\n")
    config.list_books()


proc num_pages_to_send(current_page, total_pages: int): int =
    ## This function calculates the correct number of pages to send for today.
    ##
    ## Internally it references the current month and day to determine how to
    ## finish a book of length (total_pages) by the end of the month.
    let now = times.now()
    let days_in_month = times.getDaysInMonth(now.month, now.year)

    # +1 to include the current page
    let pages_left = total_pages - current_page + 1
    result = math.floorDiv(pages_left, days_in_month - (now.monthday-1))


proc create_pdf(path_to_book, cache_dir: string, ebook_convert_args: string): string =
    ## Call ebook-convert to create a PDF from the provided book
    result = cache_dir / changeFileExt(extractFilename(path_to_book), "pdf")

    if os.fileExists(result):
        echo("PDF found, skipping conversion...")
        return result

    if splitFile(path_to_book)[2].toLowerAscii() == ".pdf":
        echo("Copying PDF to cache directory, skipping conversion...")
        copyFile(absolutePath(path_to_book), result)
        return result

    echo("Converting book to pdf...")
    let convert_command = &"ebook-convert \"{absolutePath(path_to_book)}\" \"{result}\" {ebook_convert_args}"
    let return_code = os.execShellCmd(convert_command)
    if return_code != 0:
        quit(&"Error converting {path_to_book} to PDF. Exiting.")

    return result


proc create_png_pages(path_to_pdf: string, pdftoppm_args: string): string =
    ## Create a folder of PNG pages using the supplied PDF
    let path_no_ext = changeFileExt(path_to_pdf, "")
    result = &"{path_no_ext}_pages"

    if os.dirExists(result):
        echo("PNG pages found, skipping creation...")
        return result

    let previousDir = os.getCurrentDir()
    os.createDir(result)
    os.setCurrentDir(result)

    echo("Creating PNG pages...")
    let pages_command = &"pdftoppm -png {pdftoppm_args} \"{path_to_pdf}\" page"
    discard os.execShellCmd(pages_command)

    os.setCurrentDir(previousDir)

    return result


proc create_message(from_address, to_address, subject: string, files_to_attach: seq[string]): MultipartData =
    ## Create the MultipartData message with the needed attachments

    let image_tags = files_to_attach.mapIt(&"""<img src="cid:{extractFilename(it)}">""").join("")

    let data = {
        "from": &"DailyReader <{from_address}>",
        "to": to_address,
        "subject": subject,
        "text": "There is no alternative plain text message!",
        "html": &"<html>{image_tags}</html>",
    }

    result = newMultipartData(data)
    result.addFiles(files_to_attach.mapIt((name: "inline", file: it)))

    return result


proc send_message_mailgun(multipart_message: MultipartData, api_key, api_url: string) =
    ## Make the HTTP post with the proper authorization headers
    var client = newHttpClient()

    let encoded_credentials = encode(&"api:{api_key}")
    client.headers = newHttpHeaders({"Authorization": &"Basic {encoded_credentials}"})

    echo(client.postContent(api_url, multipart = multipart_message))


when isMainModule:
    main()
