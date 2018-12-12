# DailyReader

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

## Requirements

-   Calibre (for ebook_convert)
-   pdftoppm (for the PDF->PNG process)
