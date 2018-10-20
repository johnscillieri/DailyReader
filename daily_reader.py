"""
Usage:
  daily_reader.py <epub> [--first=<first>] [--new-pages=<number>]
  daily_reader.py (-h | --help)
  daily_reader.py --version

Options:
  -f --first=<first>           First page to send
  -n --new-pages=<number>      Number of new pages to send
  -h --help                    Show this screen.
  --version                    Show version.

"""
import os
import sys

import docopt
import toml

from email_utils import create_message, send_message

VERSION = "daily_reader 0.5b"


def main():
    """ Parse args, read/write config, and call primary function """
    args = convert_args(docopt.docopt(__doc__, version=VERSION))

    # Needed for stupid Gmail auth process, it grabs any of our args for some reason
    sys.argv.pop()

    config_path = os.path.join(os.path.dirname(__file__), "config.toml")
    config = toml.load(config_path)

    book_name = os.path.basename(args.epub)

    if book_name not in config["books"]:
        config["books"][book_name] = {"first": 1, "new_pages": 5}

    book_settings = config["books"][book_name]

    if args.first:
        book_settings["first"] = int(args.first)

    if args.new_pages:
        book_settings["new_pages"] = int(args.new_pages)

    send_daily_email(
        email_address=config["email_address"],
        book_path=args.epub,
        first=book_settings["first"],
        count=book_settings["new_pages"] + 1,
    )

    book_settings["first"] += book_settings["new_pages"]
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

    total_pages = len(os.listdir(pages_folder))
    percent = int((first + count - 1) / total_pages * 100)
    page_message = f"page {first}-{first+count-1} of {total_pages} ({percent}%)"
    print(f"Sending email, {page_message}...")
    subject = f"DailyReader: {os.path.basename(book_path)} - {page_message}"
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
