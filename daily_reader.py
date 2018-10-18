"""
Usage:
  daily_reader.py <epub> [--first=<first>] [--last=<last> | --count=<count>] [--resolution=<resolution>]
  daily_reader.py (-h | --help)
  daily_reader.py --version

Options:
  -f --first=<first>             First page to send
  -l --last=<last>               Last page to send
  -r --resolution=<resolution>   Resolution to scale pages in DPI, default is 150
  -h --help                      Show this screen.
  --version                      Show version.

"""
import base64
import os
import sys

import docopt

VERSION = "daily_reader 0.3b"

"""
TODO
    Fix sending pages that are not 1-5
    create a marker file for the last page sent
    exit if page to send > last available page
    install a cron job
    pdftoppm needs a calculation to determine the optimal -r argument, it should
        auto scale to a fixed resolution (or not scale at all)
    pdftoppm - convert the short arguments to the full ones
    cleanup main function
"""


def main(args):
    full_epub_path = os.path.abspath(args.epub)
    base_name = os.path.splitext(full_epub_path)[0]

    pdf_path = f"{base_name}.pdf"
    if not os.path.exists(pdf_path):
        print("Converting epub to pdf...")
        convert_command = f'ebook-convert "{full_epub_path}" "{pdf_path}"'
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
        os.chdir(os.path.dirname(pages_folder))
    else:
        print("PNG pages found, skipping creation...")

    # This should read the marker, then either the last or count arguments
    first = 1 if not args.first else int(args.first)
    last = 5 if not args.last else int(args.last)

    print(f"Sending email, pages {first} to {last}...")
    message = create_message(pages_folder=pages_folder, first=first, last=last)
    send_message(message)

    print("Done!")


def create_message(pages_folder, first, last):
    # Send an HTML email with an embedded image and a plain text message for
    # email clients that don't want to display the HTML.

    from email.mime.multipart import MIMEMultipart
    from email.mime.text import MIMEText
    from email.mime.image import MIMEImage

    from_address = "john@scillieri.com"
    to_address = from_address

    # Create the root message and fill in the from, to, and subject headers
    msg_root = MIMEMultipart("related")
    msg_root["Subject"] = "Daily Reading"
    msg_root["From"] = from_address
    msg_root["To"] = to_address
    msg_root.preamble = "This is a multi-part message in MIME format."

    # Encapsulate the plain and HTML versions of the message body in an
    # 'alternative' part, so message agents can decide which they want to display.
    msg_alternative = MIMEMultipart("alternative")
    msg_root.attach(msg_alternative)

    msg_text = MIMEText("There is no alternative plain text message!")
    msg_alternative.attach(msg_text)

    # We reference the image in the IMG SRC attribute by the ID we give it below
    msg_text = MIMEText(
        """
        <img src="cid:image1">
        <img src="cid:image2">
        <img src="cid:image3">
        <img src="cid:image4">
        <img src="cid:image5">""",
        "html",
    )
    msg_alternative.attach(msg_text)

    # This example assumes the image is in the current directory
    os.chdir(pages_folder)
    for i in range(first, last + 1):
        input_file = f"page-{i:03}.png"
        print(f"Adding page: {input_file}...")
        fp = open(input_file, "rb")
        msg_image = MIMEImage(fp.read())
        fp.close()

        # Define the image's ID as referenced above
        msg_image.add_header("Content-ID", f"<image{i}>")
        msg_root.attach(msg_image)
    os.chdir(os.path.dirname(pages_folder))

    payload = base64.urlsafe_b64encode(msg_root.as_string().encode("ascii"))
    return {"raw": payload.decode("ascii") }


def send_message(message):
    """Send an email message.

    Args:
    service: Authorized Gmail API service instance.
    message: Message to be sent.

    Returns:
    Sent Message.
    """
    from googleapiclient.discovery import build
    from googleapiclient.errors import HttpError
    from httplib2 import Http
    from oauth2client import file, client, tools

    # If modifying these scopes, delete the file token.json.
    SCOPES = "https://www.googleapis.com/auth/gmail.send"

    """Shows basic usage of the Gmail API.
    Lists the user's Gmail labels.
    """
    store = file.Storage("token.json")
    creds = store.get()
    if not creds or creds.invalid:
        flow = client.flow_from_clientsecrets("credentials.json", SCOPES)
        creds = tools.run_flow(flow, store)
    service = build("gmail", "v1", http=creds.authorize(Http()))

    try:
        message = service.users().messages().send(userId="me", body=message).execute()
        print("Message Id: %s" % message["id"])
        return message
    except HttpError as error:
        print("An error occurred: %s" % error)


def convert_args(dictionary):
    """ Convert a docopt dict to a namedtuple """
    from collections import namedtuple

    new_dict = {}
    for key, value in dictionary.items():
        key = (
            key.replace("--", "")
            .replace("-", "_")
            .replace("<", "")
            .replace(">", "")
            .lower()
        )
        new_dict[key] = value
    return namedtuple("DocoptArgs", new_dict.keys())(**new_dict)


if __name__ == "__main__":
    arguments = convert_args(docopt.docopt(__doc__, version=VERSION))
    # Needed for stupid Gmail auth process
    sys.argv.pop()
    main(arguments)
