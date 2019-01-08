# TODO

-   Support list of books
-   Cleanup main function
-   Check for calibre binaries in path, or use config variable if not found

## List of Books TODOs

-   Keep a list of books Read/Reading/ToRead with
    -   dr run
    -   dr remove book
    -   dr add book [--position <num>]
    -   dr list
    -   dr (no arguments given, print help)
-   Cleanup the intermediate documents (pdf if epub, pngs always) when done
-   Send a message (Pick a new book!) & exit if no books in list
-   Cleanup the list of read books from the config file (on finish?)
-   Save stats for pages/books read (when finished)

## Scrap

    books = [
        { name: book1, start: 1 },
        { name: book2, start: 1 },
    ]
