# TODO

-   Move creation of intermediate documents to a local data directory
-   Handle missing config dir and missing config file
-   Write config to the user's config directory
-   Read ebook_convert arguments from config file
-   Read pdftoppm arguments from config file
-   Cleanup the intermediate documents (pdf if epub, pngs always) when done
-   Allow passing all settings via command line
-   Cleanup main function
-   Support maintaining lists of books
-   Send a message (Pick a new book!) & exit if first page > last available page

## XDG Notes

You should adhere your application to the XDG Base Directory Specification. Most answers here are either obsolete or wrong.

Your application should store and load data and configuration files to/from the directories pointed by the following environment variables:

    $XDG_DATA_HOME (default: "$HOME/.local/share"): user-specific data files.
    $XDG_CONFIG_HOME (default: "$HOME/.config"): user-specific configuration files.
    $XDG_DATA_DIRS (default: "/usr/local/share/:/usr/share/"): precedence-ordered set of system data directories.
    $XDG_CONFIG_DIRS (default: "/etc/xdg"): precedence-ordered set of system configuration directories.
    $XDG_CACHE_HOME (default: "$HOME/.cache"): user-specific non-essential data files.

You should first determine if the file in question is:

    A configuration file ($XDG_CONFIG_HOME:$XDG_CONFIG_DIRS);
    A data file ($XDG_DATA_HOME:$XDG_DATA_DIRS); or
    A non-essential (cache) file ($XDG_CACHE_HOME).

It is recommended that your application put its files in a subdirectory of the above directories. Usually, something like $XDG_DATA_DIRS/<application>/filename or$XDG_DATA_DIRS/<vendor>/<application>/filename.

When loading, you first try to load the file from the user-specific directories ($XDG_*_HOME) and, if failed, from system directories ($XDG\_\*\_DIRS). When saving, save to user-specific directories only (since the user probably won't have write access to system directories).
