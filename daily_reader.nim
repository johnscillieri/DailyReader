{.experimental: "codeReordering".}

import base64
import httpclient
import os
import parsecfg
import sequtils
import strformat
import strutils

import commandeer

template get_filename: string = instantiationInfo().filename.splitFile()[1]
const app_name = get_filename()

const version = &"{app_name} 0.8b"

const usage_text = &"""

Usage:
    {app_name} <book> [--first=<first>] [--new-pages=<number>]
    {app_name} (-h | --help)
    {app_name} --version

  Options:
    -f --first=<first>           First page to send
    -n --new-pages=<number>      Number of new pages to send
    -h --help                    Show this screen.
    --version                    Show version.
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
        option first, int, "first", "f"
        option new_pages, int, "new-pages", "n"
        exitoption "help", "h", full_help_text
        exitoption "version", "v", version
        errormsg usage_text

    let full_book_path = absolutePath(book)

    let path_to_pdf = create_pdf(full_book_path)

    let pages_folder = create_png_pages(path_to_pdf)

    var files_to_attach: seq[string] = @[]
    for i in first..(first+new_pages):
        let current_page = absolutePath(pages_folder / &"page-{i:03}.png")
        files_to_attach.add(current_page)

    # let book_base_name = os.splitFile(book)[1]
    # var config = loadConfig("config.cfg")
    # let email_address = config.getSectionValue("", "email_address")
    # let first_config = config.getSectionValue(book_base_name, "first")
    # let count_config = config.getSectionValue(book_base_name, "count")
    # let mailgun_sender = config.getSectionValue("mailgun", "sender")
    # let mailgun_api_key = config.getSectionValue("mailgun", "api_key")
    # let mailgun_api_url = config.getSectionValue("mailgun", "api_url")
    # let subject = &"DailyReader: {os.splitFile(full_book_path)[1]}"

    # let multipart_message = create_message(mailgun_sender, email_address, subject, files_to_attach) 
    # send_message_mailgun(multipart_message, mailgun_api_key, mailgun_api_url)

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

    echo("Creating PNG pages...")
    let previousDir = os.getCurrentDir()
    os.createDir(result)
    os.setCurrentDir(result)
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
