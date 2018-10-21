{.reorder: on.}

import base64
import httpclient
import os
import parsecfg
import strformat

import commandeer

template get_filename: string = instantiationInfo().filename.splitFile()[1]
const app_name = get_filename()

const version = "daily_reader 0.8b"

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


proc main() =
    commandline:
        argument book, string
        option first, int, "first", "f"
        option new_pages, int, "new-pages", "n"
        exitoption "help", "h", full_help_text
        exitoption "version", "v", version
        errormsg usage_text

    var config = loadConfig("config.cfg")
    echo config.getSectionValue("books.EffectiveExecutive.pdf", "first")

    config.setSectionKey("", "email_address", "John@Scillieri.com")
    echo config

    echo "Arguments:"
    echo book
    echo new_pages
    echo first
    # send_email(book)


proc send_email(book, mailgun_api_key, mailgun_sender, mailgun_api_url: string) =
    var client = newHttpClient()

    let encoded_credentials = encode(&"api:{mailgun_api_key}")
    client.headers = newHttpHeaders({"Authorization": &"Basic {encoded_credentials}"})

    let data = {
        "from": &"DailyReader <{mailgun_sender}>",
        "to": "John Scillieri <john@scillieri.com>",
        "subject": &"DailyReader: {book}",
        "text": "Congratulations John Scillieri, you just sent an email with Mailgun!  You are truly awesome!",
        "html": "<html>Inline image here: <img src=\"cid:page-037.png\"></html>",
    }
    var multipart = newMultipartData(data)
    multipart.addFiles({"inline": "books/EffectiveExecutive_pages/page-037.png"})
    echo client.postContent(mailgun_api_url, multipart = multipart)


when isMainModule:
    main()
