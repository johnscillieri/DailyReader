"""
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

Usage:
  daily_reader.py <book> [--first=<first>] [--new-pages=<number>]
  daily_reader.py (-h | --help)
  daily_reader.py --version

Options:
  -f --first=<first>           First page to send
  -n --new-pages=<number>      Number of new pages to send
  -h --help                    Show this screen.
  --version                    Show version.

"""
import base64
import os
import sys
from collections import namedtuple
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.mime.image import MIMEImage

import docopt
import googleapiclient.discovery
import googleapiclient.errors
import httplib2
import oauth2client.client
import oauth2client.file
import oauth2client.tools
import toml


VERSION = "daily_reader 0.7b"


def main():
    """ Parse args, read/write config, and call primary function """
    args = convert_args(docopt.docopt(__doc__, version=VERSION))

    config_path = os.path.join(os.path.dirname(__file__), "config.toml")
    if os.path.exists(config_path):
        config = toml.load(config_path)
    else:
        email_address = input("Please provide an email address to use: ")
        config = {"books": {}, "email_address": email_address.strip()}

    book_name = os.path.basename(args.book)

    if book_name not in config["books"]:
        config["books"][book_name] = {"first": 1, "new_pages": 5}

    book_settings = config["books"][book_name]

    if args.first:
        book_settings["first"] = int(args.first)

    if args.new_pages:
        book_settings["new_pages"] = int(args.new_pages)

    send_daily_email(
        email_address=config["email_address"],
        book_path=args.book,
        first=book_settings["first"],
        count=book_settings["new_pages"] + 1,
    )

    book_settings["first"] += book_settings["new_pages"]
    with open(config_path, "w") as output_handle:
        toml.dump(config, output_handle)

    print("Done!")


def send_daily_email(email_address, book_path, first=1, count=5):
    """ Send the specified pages of the book to the given email address """
    full_book_path = os.path.abspath(book_path)
    base_name = os.path.splitext(full_book_path)[0]

    pdf_path = f"{base_name}.pdf"
    if not os.path.exists(pdf_path):
        print("Converting book to pdf...")
        convert_command = f'ebook-convert "{full_book_path}" "{pdf_path}"'
        os.system(convert_command)
    else:
        print("PDF found, skipping conversion...")

    pages_folder = f"{base_name}_pages"
    if not os.path.exists(pages_folder):
        print("Creating PNG pages...")
        os.mkdir(pages_folder)
        os.chdir(pages_folder)
        pages_command = f'pdftoppm -png -f 1 -l 0 -r 125 "{pdf_path}" page'
        os.system(pages_command)
        os.chdir(os.path.dirname(__file__))
    else:
        print("PNG pages found, skipping creation...")

    total_pages = len(os.listdir(pages_folder))
    percent = int((first + count - 1) / total_pages * 100)
    page_message = f"page {first}-{first+count-1} of {total_pages} ({percent}%)"
    print(f"Sending email, {page_message}...")
    subject = f"DailyReader: {os.path.basename(book_path)} - {page_message}"
    message = create_message(
        email_address=email_address,
        subject=subject,
        pages_folder=pages_folder,
        first=first,
        count=count,
    )
    send_message(message)


def create_message(email_address, subject, pages_folder, first, count):
    """ Create a message that has the correct number of attachments """

    # Create the root message and fill in the from, to, and subject headers
    msg_root = MIMEMultipart("related")
    msg_root["Subject"] = subject
    msg_root["From"] = email_address
    msg_root["To"] = email_address
    msg_root.preamble = "This is a multi-part message in MIME format."

    # Encapsulate the plain and HTML versions of the message body in an
    # 'alternative' part, so message agents can decide which they want to display.
    msg_alternative = MIMEMultipart("alternative")
    msg_root.attach(msg_alternative)

    msg_text = MIMEText("There is no alternative plain text message!")
    msg_alternative.attach(msg_text)

    # We reference the image in the IMG SRC attribute by the ID we give it below
    msg_text = "".join([f'<img src="cid:image{i}">' for i in range(first, first + count)])
    msg_alternative.attach(MIMEText(msg_text, "html"))

    for i in range(first, first + count):
        input_file = os.path.join(pages_folder, f"page-{i:03}.png")
        print(f"Adding page: {input_file}...")
        with open(input_file, "rb") as input_handle:
            msg_image = MIMEImage(input_handle.read())

        # Define the image's ID as referenced above
        msg_image.add_header("Content-ID", f"<image{i}>")
        msg_root.attach(msg_image)

    return msg_root


def send_message(message):
    """ Send a MIMEMultipart email message via gmail """

    token_file = os.path.join(os.path.dirname(__file__), "token.json")
    creds_file = os.path.join(os.path.dirname(__file__), "credentials.json")

    store = oauth2client.file.Storage(token_file)
    creds = store.get()
    if not creds or creds.invalid:
        # Needed for stupid Gmail auth process, it grabs our args for some reason
        sys.argv.pop()

        # If modifying these scopes, delete the file token.json.
        authorization_scope = "https://www.googleapis.com/auth/gmail.send"
        flow = oauth2client.client.flow_from_clientsecrets(creds_file, authorization_scope)
        creds = oauth2client.tools.run_flow(flow, store)

    service = googleapiclient.discovery.build("gmail", "v1", http=creds.authorize(httplib2.Http()))

    payload = base64.urlsafe_b64encode(message.as_string().encode("ascii"))
    gmail_payload = {"raw": payload.decode("ascii")}

    try:
        message = service.users().messages().send(userId="me", body=gmail_payload).execute()
        return message
    except googleapiclient.errors.HttpError as error:
        print("An error occurred: %s" % error)


def convert_args(dictionary):
    """ Convert a docopt dict to a namedtuple """
    new_dict = {}
    for key, value in dictionary.items():
        key = key.replace("--", "").replace("-", "_")
        key = key.replace("<", "").replace(">", "").lower()
        new_dict[key] = value
    return namedtuple("DocoptArgs", new_dict.keys())(**new_dict)


if __name__ == "__main__":
    main()
