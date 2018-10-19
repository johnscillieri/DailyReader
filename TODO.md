# TODO

-   Include the page numbers in the email subject
-   Check if we can just email pages of the PDF?
    -   pdftk full-pdf.pdf cat 12-15 output outfile_p12-15.pdf
-   Include the last prior page in today's email (for context)
-   Update the README with more info on what it does & how it works
-   Take the absolute path to the epub for the config file
-   Send a message (Pick a new book!) & exit if first page > last available page
-   Cleanup main function
-   Create default config.toml if not found & remove from git

## PDF to PPM

These may be obsolete if gmail handles PDFs well:

-   Calculate the optimal -r argument, should auto scale to a fixed resolution (or not scale at all)
-   Convert the short arguments to the full ones in the os.system call
