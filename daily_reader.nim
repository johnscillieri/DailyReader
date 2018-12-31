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

const version = &"{app_name} 0.9b"

const usage_text = &"""

Usage:
    {app_name} <book> [--start=<start>] [--new-pages=<number>] [--force]
    {app_name} (-h | --help)
    {app_name} (-v | --version)

  Options:
    -s --start=<page num>        Page number to start from
    -n --new-pages=<number>      Number of new pages to send
    -F --force                   Override the 20 page max safety check
    -f --from=<address>          Email address to send from
    -t --to=<address>            Email address to send to
    -U --mailgun-url=<url>       Mailgun API URL
    -K --mailgun-key=<key>       Mailgun API Key

    -h --help                    Show this screen.
    -v --version                 Show version.
"""

const full_help_text = &"""
{version}

Automates emailing pages from a book, keeping track of where you left off.

Useful as a cron job to create a regular reading habit.

Converts the book to a PDF for a stable rendering, then splits the pages of the
pdf into individual PNGs to include inline in an email.

Should support any format supported by Calibre (epub, mobi, pdf, etc)

The --new-pages argument is the number of NEW pages to send. The last page of
the prior batch is included as the first page of the next email so the reader
can maintain context. For example, if --new-pages is set to 5, and your last
batch was pages 5-10, the next email that gets sent will be six pages long,
pages 10-15, inclusive.
{usage_text}
"""

## TODO - Break this up into parsing args & config & sending the message
proc main() =
    commandline:
        argument book, string
        option start_arg, int, "start", "s"
        option new_pages_arg, int, "new-pages", "n"
        option force, bool, "force", "F"
        exitoption "help", "h", full_help_text
        exitoption "version", "v", version
        errormsg usage_text

    let config_dir = os.getConfigDir() / app_name
    createDir(config_dir)
    let cache_dir = get_cache_dir(app_name)
    createDir(cache_dir)

    let config_file_path = config_dir / "config.toml"
    var config = parseFile(config_file_path)

    let email_address = config{"email", "address"}.getStr("")
    let mailgun_sender = config{"email", "mailgun", "sender"}.getStr("")
    let mailgun_api_key = config{"email", "mailgun", "api_key"}.getStr("")
    let mailgun_api_url = config{"email", "mailgun", "api_url"}.getStr("")

    if email_address == "":
        echo("ERROR: Missing required email address config value")
        return

    if mailgun_sender == "" or mailgun_api_key == "" or mailgun_api_url == "":
        echo("ERROR: Missing one of the required mailgun settings: sender, api_key, or api_url")
        return

    let path_to_pdf = create_pdf(book, cache_dir)

    let pages_folder = create_png_pages(path_to_pdf)
    let total_pages = len(toSeq(walkFiles(&"{pages_folder}/*.png")))

    let book_base_name = os.splitFile(book)[1]
    let start_config = config{"books", book_base_name, "start"}.getInt(1)
    let start = if start_arg != 0: start_arg else: start_config

    let new_pages_default = num_pages_to_send( current_page=start, total_pages=total_pages )
    let new_pages = if new_pages_arg != 0: new_pages_arg else: new_pages_default
    echo(&"Current Page: {start}, preparing to send {new_pages} pages...")

    let percent = int((start + new_pages - 1) / total_pages * 100)
    let subject = &"DailyReader: {os.splitFile(book)[1]} - page {start}-{start+new_pages-1} of {total_pages} ({percent}%)"
    echo(subject)

    # TODO - make this a setting in the config file
    if new_pages > 20 and force == false:
        echo("ERROR: Attempting to send more than 20 pages without the force flag.")
        return

    var files_to_attach: seq[string] = @[]
    # start-1 so that you send the last previously read page for context
    for i in (start-1)..<(start+new_pages):
        let current_page = absolutePath(pages_folder / &"page-{i:03}.png")
        if os.fileExists(current_page):
            files_to_attach.add(current_page)
            echo(&"Added {current_page}...")

    let multipart_message = create_message(mailgun_sender, email_address, subject, files_to_attach)
    send_message_mailgun(multipart_message, mailgun_api_key, mailgun_api_url)

    config{"books", book_base_name, "start"} = ?(start+new_pages)
    writeFile(config_file_path, config.toTomlString())

    echo("Done!")


proc get_cache_dir( app_name: string ): string =
    ## Read the path to the user's temporary cache directory
    result = getEnv("XDG_CACHE_HOME")
    if result != "":
        return result / app_name

    if existsEnv("HOME") == false:
        echo("WARNING: Couldn't read $XDG_CACHE_HOME or $HOME. Using the current application directory as the cache file location.")
        return getAppDir()

    return getEnv("HOME") / ".cache" / app_name


proc num_pages_to_send( current_page, total_pages: int ): int =
    ## This function calculates the correct number of pages to send for today.
    ##
    ## Internally it references the current month and day to determine how to
    ## finish a book of length (total_pages) by the end of the month.
    let now = times.now()
    let days_in_month = times.getDaysInMonth(now.month, now.year)

    # +1 to include the current page
    let pages_left = total_pages - current_page + 1
    result = math.floorDiv(pages_left, days_in_month - (now.monthday-1))


proc create_pdf(path_to_book, cache_dir: string): string =
    ## Call ebook-convert to create a PDF from the provided book
    result = cache_dir / changeFileExt(extractFilename(path_to_book), "pdf")

    if os.fileExists(result):
        echo("PDF found, skipping conversion...")
        return result

    if splitFile(path_to_book)[2] == "pdf":
        echo("Copying PDF to cache directory, skipping conversion...")
        copyFile(absolutePath(path_to_book), result)
        return result

    echo("Converting book to pdf...")
    let convert_command = &"ebook-convert \"{absolutePath(path_to_book)}\" \"{result}\" --pdf-page-margin-bottom=36 --pdf-page-margin-top=18 --pdf-page-numbers --pdf-default-font-size=24"
    discard os.execShellCmd(convert_command)
    return result


proc create_png_pages(path_to_pdf: string): string =
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
    let pages_command = &"pdftoppm -png -f 1 -l 0 \"{path_to_pdf}\" page"
    discard os.execShellCmd(pages_command)

    os.setCurrentDir(previousDir)

    return result


proc create_message( from_address, to_address, subject: string, files_to_attach: seq[string]): MultipartData =
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
    result.addFiles(files_to_attach.mapIt((name:"inline", file:it)))

    return result


proc send_message_mailgun(multipart_message: MultipartData, api_key, api_url: string ) =
    ## Make the HTTP post with the proper authorization headers
    var client = newHttpClient()

    let encoded_credentials = encode(&"api:{api_key}")
    client.headers = newHttpHeaders({"Authorization": &"Basic {encoded_credentials}"})

    echo(client.postContent(api_url, multipart = multipart_message))


when isMainModule:
    main()
