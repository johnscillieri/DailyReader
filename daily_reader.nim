{.experimental: "codeReordering".}

import base64
import httpclient
import os
import sequtils
import strformat
import strutils

import commandeer
import parsetoml

template get_filename: string = instantiationInfo().filename.splitFile()[1]
const app_name = get_filename()

const version = &"{app_name} 0.8b"
let config_path = getAppDir() / "config.toml"

const usage_text = &"""

Usage:
    {app_name} <book> [--first=<first>] [--new-pages=<number>]
    {app_name} (-h | --help)
    {app_name} (-v | --version)

  Options:
    -f --first=<first>           First page to send
    -n --new-pages=<number>      Number of new pages to send
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
        option first_arg, int, "first", "f"
        option new_pages_arg, int, "new-pages", "n"
        exitoption "help", "h", full_help_text
        exitoption "version", "v", version
        errormsg usage_text

    var config = parseFile(config_path)

    let book_base_name = os.splitFile(book)[1]
    let first_config = config{"books", book_base_name, "first"}.getInt(1)
    let new_pages_config = config{"books", book_base_name, "new_pages"}.getInt(5)

    let first = if first_arg != 0: first_arg else: first_config
    let new_pages = if new_pages_arg != 0: new_pages_arg else: new_pages_config

    let full_book_path = absolutePath(book)

    let path_to_pdf = create_pdf(full_book_path)

    let pages_folder = create_png_pages(path_to_pdf)

    var files_to_attach: seq[string] = @[]
    for i in first..(first+new_pages):
        let current_page = absolutePath(pages_folder / &"page-{i:03}.png")
        files_to_attach.add(current_page)

    let email_address = config{"email_address"}.getStr("")
    let mailgun_sender = config{"mailgun", "sender"}.getStr("")
    let mailgun_api_key = config{"mailgun", "api_key"}.getStr("")
    let mailgun_api_url = config{"mailgun", "api_url"}.getStr("")

    if email_address == "":
        echo("ERROR: Missing required email_address: run again with a -e to set.")
        return

    if mailgun_sender == "" or mailgun_api_key == "" or mailgun_api_url == "":
        echo("ERROR: Missing one of the required mailgun settings: sender, api_key, or api_url")
        return

    let total_pages = len(toSeq(walkFiles(&"{pages_folder}/*.png")))
    let percent = int((first + new_pages - 1) / total_pages * 100)
    let subject = &"DailyReader: {os.splitFile(full_book_path)[1]} - page {first}-{first+new_pages-1} of {total_pages} ({percent}%)"
    echo(subject)

    let multipart_message = create_message(mailgun_sender, email_address, subject, files_to_attach)
    send_message_mailgun(multipart_message, mailgun_api_key, mailgun_api_url)

    config{"books", book_base_name, "first"} = ?(first+new_pages)
    config{"books", book_base_name, "new_pages"} = ?new_pages
    writeFile(config_path, config.toTomlString())

    echo("Done!")


proc create_pdf(path_to_book: string): string =
    ## Call ebook-convert to create a PDF from the provided book
    result = changeFileExt(path_to_book, "pdf")

    if os.fileExists(result):
        echo("PDF found, skipping conversion...")
        return result

    echo("Converting book to pdf...")
    let convert_command = &"ebook-convert \"{path_to_book}\" \"{result}\""
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
    let pages_command = &"pdftoppm -png -f 1 -l 0 -r 125 \"{path_to_pdf}\" page"
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
