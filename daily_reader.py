"""
Usage:
  daily_reader.py <epub> [--first=<first>] [--count=<count>] [--resolution=<resolution>]
  daily_reader.py (-h | --help)
  daily_reader.py --version

Options:
  -f --first=<first>             First page to send
  -c --count=<count>             Number of pages to send
  -r --resolution=<resolution>   Resolution to scale pages in DPI, default is 150
  -h --help                      Show this screen.
  --version                      Show version.

"""
import os
import sys

import docopt
import toml

from email_utils import create_message, send_message

VERSION = "daily_reader 0.3b"

"""
TODO
    exit if page to send > last available page
    install a cron job
    pdftoppm needs a calculation to determine the optimal -r argument, it should
        auto scale to a fixed resolution (or not scale at all)
    pdftoppm - convert the short arguments to the full ones
    cleanup main function
    take the absolute path to the epub for the config file
    include the page numbers in the email subject
"""


def main():
    """ Parse args, read/write config, and call primary function """
    args = convert_args(docopt.docopt(__doc__, version=VERSION))

    # Needed for stupid Gmail auth process, it grabs any of our args for some reason
    sys.argv.pop()

    config_path = os.path.join(os.path.dirname(__file__), "config.toml")
    config = toml.load(config_path)
    if args.epub not in config["books"]:
        config["books"][args.epub] = {"first": 1, "count": 5}

    book_settings = config["books"][args.epub]

    if args.first:
        book_settings["first"] = int(args.first)

    if args.count:
        book_settings["count"] = int(args.count)

    send_daily_email(
        email_address=config["email_address"],
        book_path=args.epub,
        first=book_settings["first"],
        count=book_settings["count"],
    )

    book_settings["first"] += book_settings["count"]
    with open(config_path, "w") as output_handle:
        toml.dump(config, output_handle)

    print("Done!")


def send_daily_email(email_address, book_path, first=1, count=5):
    full_epub_path = os.path.abspath(book_path)
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

    print(f"Sending email, pages {first} to {first+count-1}...")
    subject = f"Daily Reading - {os.path.basename(book_path)}"
    message = create_message(
        email_address=email_address, subject=subject, pages_folder=pages_folder, first=first, count=count
    )
    send_message(message)


def convert_args(dictionary):
    """ Convert a docopt dict to a namedtuple """
    from collections import namedtuple

    new_dict = {}
    for key, value in dictionary.items():
        key = key.replace("--", "").replace("-", "_").replace("<", "").replace(">", "").lower()
        new_dict[key] = value
    return namedtuple("DocoptArgs", new_dict.keys())(**new_dict)


if __name__ == "__main__":
    main()
