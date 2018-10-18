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
import os
import sys

import docopt

from email_utils import create_message, send_message

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


def convert_args(dictionary):
    """ Convert a docopt dict to a namedtuple """
    from collections import namedtuple

    new_dict = {}
    for key, value in dictionary.items():
        key = key.replace("--", "").replace("-", "_").replace("<", "").replace(">", "").lower()
        new_dict[key] = value
    return namedtuple("DocoptArgs", new_dict.keys())(**new_dict)


if __name__ == "__main__":
    arguments = convert_args(docopt.docopt(__doc__, version=VERSION))
    # Needed for stupid Gmail auth process
    sys.argv.pop()
    main(arguments)
