README for movemetafs
by pts@fazekas.hu at Thu Jan  4 14:48:21 CET 2007

movemetafs is a searchable filesystem metadata store for Linux, which lets
users tag local files (including image, video, audio and text files) by
simply moving the files to a special folder using any file manager, and it
also lets users find files by tags, using a boolean search query. The
original files (and their names) are kept intact. movemetafs doesn't have
its own user interface, but it is usable with any file manager.

In the name `movemetafs', `metafs' means filesystem metadata store, and
`move' refers to the most common way tags are added or removed: the user
moves the file to be affected to the meta/tag/$TAGNAME or
meta/untag/$TAGNAME special folder. When the target folder is such a special
folder, the file is not removed from its original location (meta/root/**/*).

movemetafs is similar to LAFS (http://junk.nocrew.org/~stefan/lafs/)
(not tagji 1.1 by Manuel Arriaga). Most important differences:

-- movemetafs uses MySQL instead of PostgreSQL (benefits: speedup, easier
   installation with pts-mysql-local)
-- movemetafs doesn't require files to be explicitly added
-- movemetafs cannot list all untagged files quickly

Features:

-- use any file manager to tag (or untag) files: move the file to the
   `meta/tag/$TAGNAME' or `meta/untag/$TAGNAME' folder
-- specify search query by changing to the invisible `meta/search/$QUERYSTRING'
   folder
-- use versatile search query syntax (MySQL fulltext search) with the
   possiblity of boolean search (i.e. searching for files matching a
   combination of tags)
-- copy search results to make backups or to create collections
-- Searching is fast, because it uses a fulltext index.
-- After installation, movemetafs can be used on an existing filesystem
   instantly: there is no migration needed to make an existing filesystem usable with
   movemetafs: data doesn't have to be copied, moved, touched etc.
-- Untagged files don't have any negative effect on the speed of movemetafs,
   even if the filesystem contains millions of files.
-- movemetafs nicely survives a system crash: non-cache data is stored in
   MySQL InnoDB tables (which use journaling), and even if the whole tag
   database is lost, the original filesystem remains usable without
   movemetafs.
-- Stores tags in twice: once in a fulltext indexed column in a MyISAM
   table, and once in an InnoDB relational table. Uses the fast MyISAM
   table for searches, and the InnoDB table for data recovery.

Current limitations:

-- cannot cross filesystem boundaries. This means that tags cannot be added
   to (or removed from) files not on the carrier filesystem (--root-prefix=).
   No other restrictions are present when accessing `meta/root'.
-- alpha software, ready for local use only
-- cannot cross filesystem boundaries
-- doesn't survive a mkfs + rsync migration
-- tags are lost when the file is copied (use md5sums?)
-- filesystem encoding is fixed (opaque, not converted to UTF-8)
-- no quick way for
-- no large file support (maximum file size is 2GB -- limitation of the Fuse
   Perl module)
-- works only with systems with FUSE support (such as Linux)
-- stale tags are not removed automatically
-- installation and user documentation is incomplete
-- not easy to install (i.e. with package)
-- no multiuser support yet (i.e. users cannot share their tags)
-- only one containing foldr is displayed for search results
-- search result symlink might be stale (i.e. it may not point to the
   correct target file) if the file has been moved outside the control of
   movemetafs
-- FUSE is a little slower than other layers such as Unionfs
-- Perl Fuse.pm is a little slower than writing a Fuse module in C
-- no logic structuring (such as taxonomy, thesaurus or ontology) and
   inference
-- For files with multiple (hard) links, symlinks in search results point to
   only one of filenames (usually the oldest) -- the other filenames are not
   stored by movemetafs.
-- it is not totally convenient to remove the principal instance of a tagged
   file with multiple hard links
-- POSIX extended attributes and ACLs are not mirrorred
-- searching is faster than tagging and untagging
-- tags cannot be multiple levels deep (i.e. contain `/')
-- no `$TAGNAME1 OR $TAGNAME2' searches

Requirements (install them in this order):

-- operating system capable of running FUSE (currently Linux and FreeBSD,
   movemetafs is tested only on Linux >=2.6.18)
-- Root privileges are required for some installation steps, but not for
   usage. movemetafs is just as safe as FUSE itself in a multiuser
   environment.
-- the FUSE libraries >=2.6.1 (/usr/lib/libfuse.so.?) and header files
   (/usr/include/fuse.h) (e.g. `apt-get install libfuse-dev' on Debian
   Sarge). Please note that fuse-2.6.0_rc1 is buggy (e.g. rename() always
   returns 0).
-- Perl >=5.8
-- the Fuse Perl module (install with `cpan Fuse' as root)
-- MySQL server >=4.1 (you don't have to change your existing MySQL server
   configuration if you use pts-mysql-local)
-- a recent MySQL client library (such as /usr/lib/libmysqlclient.so.*) and
   headers (such as /usr/include/mysql/mysql.h) (e.g.
   `apt-get install libmysqlclient15-dev' on Debian Sarge)
-- the DBD::mysql Perl module
-- the FUSE kernel module loaded (e.g. `modprobe fuse' as root on Linux)

Basic usage scenario (the order of the steps might vary):

1. All files to be tagged are collected together to a Linux filesystem.
2. movemetafs is installed and started.
3. Tag names are designed, empty tags are added.
4. Some files are tagged with existing tag names.
5. Searches are performed based on tag names. Search results are presented
   as symlinks to normal files. on the filesystem. The name of the symlink
   is similar to the name of the original files (but ambiguities are
   resolved).
6. As an overall effect, with movemetafs files are much easier to find, and
   it is easy to make file collection based on a specific theme.

Installation quickstart
~~~~~~~~~~~~~~~~~~~~~~~
!! this section isn't written properly

1. Download movemetafs from http://www.inf.bme.hu/~pts/ or
   http://freshmeat.net/projects/movemetafs/
2. Install the requirements (see above).
3. Mount your carrier filesystem on which you want to have metadata on.
4. Copy the mmfs_fuse.pl executable to your path.
5. Create the MySQL database (with recreate.sql).
6. Start mmfs_fuse.pl with the appropriate arguments, which will mount your
   filesystem with a new mount point.

Basic concepts: carrier and meta filesystems etc.
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
There are two filesystems: the carrier and the meta. The carrier filesystem
is the one that stores the actual files (and directory structure).
Currently, the carrier must be a mount point (or a subfolder of a mount
point) of a real filesystem not containing any other mount points -- thus a
carrier cannot span over multiple filesystems. This restriction is not
enforced (but you risk having your metadata garbled if you don't take care).
The restriction will be removed in the future.

Typically, even before installing movemetafs, you have a carrier filesystem
with a lot of files, among which you sometimes cannot easily find what you
want. So you decide that you will use a metadata store that will let you tag
your files, and later search for files based on the attached tags. A tag is
just a short string such as `vacation', `2007', `indoors', `outdoors',
`Greece', `dance', `John' and `high_quality'. Some logic databases have more
structure than simple tagging (such as taxonomy, thesaurus and ontology),
but movemetafs doesn't.

Tag names match the regexp /\A[0-9a-zA-Z_\x80-\xFF]{1,255}\Z(?!\n)/, where
255 is measured in bytes (MySQL VARCHAR(255) measures in characters.)
Tag names must be valid UTF-8. This works
with both UTF-8 and Latin-1 accented characters, and it also works with
MySQL's fulltext parser (which treats >=0x80 characters as part of the word,
try with U+00F7). Tag names are case-insensitive, accent-insensitive and
trailing-space-insensititve,
according to MySQL `COLLATE utf8_general_ci'. See also
http://dev.mysql.com/doc/mysql/en/charset-unicode-sets.html .

The meta filesystem (in movemetafs terminology) is a enhanced mirror view of
the corresponding carrier filesystem with extended functionality such as
tagging and searching. The view is available in a folder named `root' in the
meta filesystem, the so called `meta/root' folder. Each time you modify a
file in the meta filesystem, it is immediately modified on the carrier, too.
If you move a file within the meta filesystem, the effect becomes immediately
visible in the carrier. The meta filesystem has other folders besides the
`root', for example `tag' can be used for adding (and partially viewing)
tags, `untag' for removing tags, and `search' for searching. All
functionality of these special folders can be used from any file manager
(recommended: Midnight Commander), the exact way how to do it is documented
later.

movemetafs stores metainformation (such as which file has what tags
associated to it) in a MySQL database, which can be located anywhere: any
folder on the local machine, or even on a remote host. A remote host is not
recommended, though, because network transmission might be slow.

Warning about moving files: If you want to move a file within the filesystem
(or remove a file), do it in meta/root, not directly on the carrier. That's
because movemetafs has to track the changes in the names of the files it
manages, so it can report proper symlinks in search results. If you move a
tagged file in the carrier filesystem, the next time this file appears in a
search result (in meta/search/*), its symlink will be stale, i.e. it will
point to nowhere.

When you remove (the last link to) a file (or move it outside the meta
filesystem), movemetafs forgets all associated tags permanently.

Principal name: Files with multiple hard links share the same set of tags.
Such a tagged file has a principal name (which is returned in symlinks in
search results, and which was assigned the file was first tagged, or later,
when it was last renamed). For safety reasons, movemetafs gives the EPERM
error when you attempt to remove (unlink) the principal name of a file with
multiple hard links. To remove such a name A, locate another name B first
(might involve a slow find(1) with `-inum ...'), rename the other name B (to
B1), rename B1 back to B (thus making B the principal name of the file),
then remove A.

Short name: each tagged file has a short name, which is displayed as the
name of the symlink in search results. The short name is generated from the
principal name (keeping only the last path component, the filename),
shortening it to 255 bytes when necessary, and adding a unique prefix
of the form `:<ino-hex>:<fs>:' if multiple files have the same shortened
principal, shortened again if necessary.

In the current version of movemetafs, tagged files cannot span multiple
filesystems, i.e. all of them must have the same st_dev value in their
lstat(2) structure, and this st_dev value must be the same as the value for
the root folder of the carrier filesystem (--root-prefix=). This is
automatically ensured if --root-prefix= doesn't have any mount points deep
inside it (check it in /proc/mounts). Attempts to tag or untag files with a
different st_dev value will result in a `Remote I/O error' (EREMOTEIO).
No other restrictions are present when accessing files with different
st_dev value in `meta/root'.

movemetafs handles filenames as opaque 8-bit strings (thus filenames can be
in any character set, or in a mixture of character sets). All characters are
allowed in filenames (except for `/' and "\0", of course, which are not
allowed in any UNIX filename). Maximum filename length (checked by both
MySQL and Linux) is 255 bytes.

movemetafs refuses to add tags with a nome not in UTF-8. The software makes
no attempt to convert to UTF-8 from a local character set specified by the
locale (LC_CTYPE etc.) -- because this information is not available to FUSE.
MySQL `COLLATE utf8_general_ci' is used for sorting and comparing tags
(which is case-insensitive, accent-insensitive and
trailing-space-insensitive), see above.

How to use
~~~~~~~~~~
After installation, mount the meta filesystem by running mmfs_fuse.pl
with the appropriate command-line arguments. Usually it is enough to
specify --root-prefix= and --mount-point=. If necessary, specify --quiet.

The most important options for mmfs_fuse.pl:

-- --root-prefix=<dir>: the carrier filesystem folder, this will be
   visible as `meta/root'. This option is recommended (default: current
   directory of the ./mmfs_fuse.pl program invocation).
-- --mount-point=<dir>: folder writable by you to which the meta
   filesystem is mounted, i.e. `meta/root' will be `<dir>/root'. This option
   is mandatory.
-- --quiet: specify it to suppress debug messages and speed up mmfs_mount.pl
   a little bit.

Please remember the command-line options (especially --root-prefix=),
because finding tagged files might not work if some crucial options are
different when remounting it later.

The mmfs_fuse.pl script should remain running while you want to access the
filesystem, so it is recommended to start the script inside screen(1). If
mmfs_fuse.pl dies, you have to unmount the meta filesystem with `fusermount
-u /path/to/meta' before mounting it again. All these operations can be done
as a regular user (root is not necessary).

After starting mmfs_fuse.pl, the writable mirror view of the carrier
filesystem (--root-prefix=) becomes available as meta/root, with the
following limitations:

-- For all write operations (except for modifying file bytes withing the
   first 2GB of the file), please use meta/root, not the carrier. See also
   ``Warning about moving files'' above for the reasons. There are no such
   restrictions on read operations (except that reading beyond 2GB will
   fail), you can use the carrier or meta/root, which is a little slower.
-- Large files are not supported (by the Fuse Perl module, v0.08). Thus
   reading or writing bytes beyond the first 2GB of the file will fail. If
   you really really need to read or write past that limit, use the carrier
   filesystem instead.
-- Setting or getting POSIX extended attributes (or ACLs) is not supported.
   The lack of support for setting is the limitation of the Fuse Perl
   module, v0.08.
-- meta/root is a little slower than the carrier (because all data is copied
   to user space, to mmfs_fuse.pl). If you absolutely need performance, use
   the carrier.

Special operations with files in meta/root:

-- If a file is moved (or, equivalently, renamed) inside meta/root, its
   principal name is changed to the new name. Most of the files have link
   count of 1, thus this should be the correct behaviour. Renaming can be
   used to deliberately change the principal name of a file with multiple
   hard links. See also ``Principal name''.
-- If a file has multiple hard links, its principal name is not allowed
   to be removed (Operation not permitted, EPERM). This a a safety feature
   that prevents the `files.principal' column getting stale. See more
   in ``Principal name''.
-- `getfattr -d -e text meta/root/.../$FILENAME' displays all tags associated with
   the file in the `user.tags' field.

Besides `meta/root', there are also some special folders ain `meta/', which
behave quite differently from regular filesystems. Permissions and
ownerships in these folders don't matter. Files on the carrier are not
accessible form special folders (except through symlinks pointing inside
`meta/root').

Special folders are:

-- meta/tag
   -- `meta/tag' and its contents are not writable except for the
      operations listed below.
   -- Listing `meta/tag' yields all of the tags known by the system, each as a
      directory.
   -- Listing `meta/tag/$TAGNAME' is equivalent to listing
      `meta/search/+$TAGNAME' except for the relevance order,
      i.e. it lists all files having that tag.
   -- Creating a new folder in `meta/tag' creates a tag by that name in the
      system. Please note
      it is an error (Invalid argument) to add a non-UTF-8 tag name. Since
      tag names are case-insensitive and accent-insensitive, it is not
      possible (File exists) to add a tag `BaR' after `bar' has been added.
   -- Removing a folder in `meta/tag/' removes the specified tag from the
      system. This is not possible (Directory not empty, ENOTEMPTY)
      if there are files tagged with it. Tag removal never happens
      automatically.
   -- Moving a file from `meta/root/...' (or `meta/tag/' or `meta/untag/'
      or `meta/search/' etc.) to
      `meta/tag/$TAGNAME' adds the tag named $TAGNAME to the specific file,
      and the file is _not_ removed from its original place (and its old
      tags are not changed either). Moving files from the carrier
      into `meta/tag/.../' won't ever work -- move files from
      `meta/root/...' instead. If move doesn't work (e.g. with mv(1):
      `cannot overwrite non-directory'), try
      moving to `meta/tag/$TAGNAME/::' instead of `meta/tag/$TAGNAME'.

      Please note that it is possible to add tags only to regular files.
      Thus directories, sockets, pipes and device special nodes are not
      allowed to be moved to `meta/tag/$TAGNAME' (error message:
      Operation not permitted). This is a quite artificial limitation in
      movemetafs, so it might get removed in the future.
      
      It is not possible to add a tag to a file if the `meta/tag/$TAGNAME'
      directory doesn't exist (error: ENOENT). This is for protecting
      against typos in tag names.
   -- It is not possible to copy files into `meta/tag/' or to create files
      there.
   -- Removing `meta/tag/$TAGNAME/$SHORTNAME' removes $TAGNAME from the
      file specified by $SHORTNAME.
   -- Moving `meta/tag/$TAGNAME/$SHORTNAME' to `meta/tag/$ANOTHERTAGNAME/'
      doesn't remove $TAGNAME from the file specified by $SHORTNAME, but it
      adds $ANOTHERTAGNAME to the file.
   -- Renaming `meta/tag/$OLDTAGNAME' to `meta/tag/$NEWTAGNAME' renames the
      specified tag. The amount of time needed is proportional to the number
      of files $OLDTAGNAME is associated to. Renaming works with
      `meta/untag' in place of `meta/tag' for both folder names. If
      $NEWTAGNAME already exists, tags $OLDTAGNAME and $NEWTAGNAME are
      merged to $NEWTAGNAME for each file having either of them. Some
      utilities such as GNU mv(1) try to be smart and move $OLDTAGNAME
      inside `meta/tag/$NEWTAGNAME' if the latter exists (as a directory).
      This can be circumvented by adding spaces to the front or end of
      $NEWTAGNAME, for example `mv meta/tag/old "meta/tag/existing "'.
-- meta/untag
   -- `meta/untag' behaves exactly like `meta/tag', except when files are
      moved to `meta/untag/$TAGNAME', and except for `meta/tag/:all'.
   -- `meta/untag' and its contents are not writable except for the
      operations listed below.
   -- Listing meta/untag yields all of the tags known by the system, each as
      a directory.
   -- Listing `meta/untag/$TAGNAME' is equivalent to listing
      `meta/search/+$TAGNAME' except for the relevance order,
      i.e. it lists all files having that tag.
   -- Creating a new folder in `meta/untag' adds a tag by that name in the
      system. Please note
      it is an error (Invalid argument) to add a non-UTF-8 tag name. Since
      tag names are case-insensitive and accent-insensitive, it is not
      possible (File exists) to add a tag `BaR' after `bar' has been added.
   -- Removing a folder `meta/untag/' removes the specified tag from the
      system. This is not possible (Directory not empty, ENOTEMPTY)
      if there are files tagged with it. Tag removal never happens
      automatically.
   -- Moving a file from `root/...' (or `meta/tag/' or `meta/untag/'
      or `meta/search/' etc.) to
      `meta/untag/$TAGNAME' removes the tag named $TAGNAME from the
      file, and the file is _not_ removed from its original place (and its old
      tags are not changed either). If all tags are removed from a file,
      the file is removed from the metadata store, and its principal name,
      checksums etc. are lost. Tags can be added at any later time to that
      file.
   -- Removing `meta/untag/$TAGNAME/$SHORTNAME' removes $TAGNAME from the
      file specified in $SHORTNAME.
   -- It is not possible to copy files into `meta/untag/' or to create files
      there.
   -- The tag is not removed, even if all files are removed from it.
   -- The folder `meta/untag/:all' appears to be an empty folder. When
      moving a file to this folder, all tags are removed from the file.
   -- Listing the folder `meta/untag/:all' yields all files having at least
      one tag as symlinks.
   -- Removing `meta/untag/:all/$SHORTNAME' removes all tags from the
      file specified in $SHORTNAME.
   -- Renaming `meta/untag/$OLDTAGNAME' to `meta/untag/$NEWTAGNAME' renames
      the specified tag. See more about renaming tags under `meta/tag'.
-- meta/search
   -- meta/search appears to be an empty folder.
   -- meta/search and its contents are not writable.
   -- Listing (the invisible) `meta/search/$QUERYSTRING' will (re)run the
      search query specified in $QUERYSTRING, and list all resulting files as
      symlinks to the principal name of the file inside meta/root. See
      the section ``Search query strings'' for more information about query
      string syntax and the order of the files returned.
   -- `meta/search/$QUERYSTRING' uses the MySQL table `taggings', while
      `meta/tag/$TAGNAME' uses the table `tags'. Should any mismatch arise,
      `mkdir meta/repair_taggings' regenerates `taggings' from `tags'.
-- meta
   -- If the folder `meta/repair_taggings' is attempted to be created,
      movemetafs regenerates the `taggings' table from the `tags' table, and
      the operation returns `No such file or directory' on success. This
      regeneration can be quite slow, since the time needed is proprtional
      to the number of tags in the system (with multiplicity for each file
      they are associted to).
   -- All other write operations fail with `Operation not permitted'.

If you get `Transport endpoint is not connected' for a file operation in
meta/, this means mmfs_fuse.pl has crashed. This usually means there is a
software bug in movemetafs, so please report it (see section ``How to report
bugs''). To recover from a crash, just exit from all applications using
meta/ (too bad that `fuser -m meta' won't show the PIDs -- please report
this as a bug to the FUSE developers), umount meta/ with `fusermount -u
meta', and after exiting, restart `mmfs_fuse.pl'. (Upon startup,
mmfs_fuse.pl runs `fusermount -u meta' automatically. Due to a limitation in
the Fuse Perl module, it cannot do the same upon exit.)

If you get weird errors on some file operations, look at the terminal output
of mmfs_fuse.pl for lines starting with `info: diemsg: '. These lines contain
more detailed error information.

Use `mmfs_fuse.pl --quiet' to make to suppress debug messages, and make
movemetafs a little faster. (To get big speed improvements, caching should
be added, and the whole software should be reimplemented in C, and possibly
FUSE should be dropped on favour of Unionfs.)

Search query strings
~~~~~~~~~~~~~~~~~~~~
A search query string is a specification about tags. All files are returned
whose tags match the specification. For simple searches, files are returned
in decreasing order of relevance (not very important since most file
managers and ls(1) reorder the list).

MySQL fulltext search is used to find tags:

-- Simple search:

     SELECT fs, ino ... WHERE ... MATCH(tags) AGAINST('$QUERYSTRING');

   Simple search is used if $QUERYSTRING doesn't contain ASCII puctuation
   characters. $QUERYSTRING is a list of tags separated by spaces.
   
   The hide-above-50% threshold: This rule applies to simple searches
   (enforced by MySQL 5.1): if a tag appears in more than 50% of the files,
   it is considered irrelevant, and it treated as if it didn't appear at
   all. This can be counterintuitive when having only a small set of files
   with a lot of tags. If you don't like the hide-above-50% rule, enforce
   boolean search by prepending a `+' sign in front of each word in
   $QUERYSTRING. Thus, use `meta/search/+$TAGNAME' instead of
   `meta/search/$TAGNAME' to search all instances of a specific tag.

-- Boolean search:

     SELECT fs, ino ... WHERE ...
     MATCH(tags) AGAINST('$QUERYSTRING' IN BOOLEAN MODE);

   Boolean search used if $QUERYSTRING contains ASCII puctuation characters.
   Please note that relevance (order) is not quite intuitive in boolean search.
   
   The hide-above-50% thresold doesn't apply to boolean search.
   
   Read more about specifying MySQL fulltext boolean search queries on
   http://dev.mysql.com/doc/mysql/en/fulltext-boolean.html .
   All operators defined there work, including `*' to match the prefix of
   tag names.

Read more about specifying MySQL fulltext search queries on
http://dev.mysql.com/doc/mysql/en/fulltext-search.html and
http://dev.mysql.com/doc/mysql/en/fulltext-boolean.html .

Please note that minimum word length can be assumed to be 1, and there are
no stop words. This is accomplished by the following transformation on
the words of `tags':

-- `qqa' is appended to 1-character words 
-- `qb'  is appended to 2-character words
-- `k'   is appended to 3-character words
-- 'q'   is appended to words longer than 3 characters

There is no point quoting multiple words in `"' in the query string, because
the word order in `tags' is undefined.

MySQL fulltext search supports only the _and_ logic operation (i.e. it
doesn't support _or_), so it is not possible to search for all files having
tag A or B in one query string (with a little exception of the `*' operator
and the `(' ... ')' grouping operator).

To search for files having a single tag only, you can use either
`meta/tag/$TAGNAME' or `meta/search/+$TAGNAME'. To search for files having
both of two tags, use `meta/serach/+$TAG1NAME +$TAG2NAME' with the space. It
is not possible to exactly search for files having any of two tags (this is
a MySQL fulltext search limitation), but this usually works, even for tags
above the 50% threshold: `meta/serach/($TAG1NAME $TAG2NAME)'.

Design decisions
~~~~~~~~~~~~~~~~
!! write more here

Search results (meta/search/$QUERYSTRING/*) and files listing as tagged
(meta/tag/$TAGNAME/* and meta/untag/$TAGNAME/*) are symlinks.

The two tables `taggings' and `tags' are redundant. The reason why we have two
tables is that `taggings' cannot be protected by journaling (because InnoDB
tables cannot contain fulltext indexes in MySQL 5.1), and the fast and
specific fulltext search is only available in the `taggings' MyISAM table.
If, by any chance, `taggings' is lost in a database server crash,
it can be regenerated next time from `tags' by `mkdir meta/repair_taggings'.

Why did we choose Linux?

-- We like all Unix systems in general, however FUSE doesn't run on many
   systems: it is stable on Linux, and it is reported to run on FreeBSD.
   Since we use mostly Linux for everyday work and software development,
   we test movemetafs mostly on Linux.

Why did we choose MySQL?

-- It is possible to use another RDBMS in general, but we don't have the
   human resources right now to develop for more than one. The toughest
   part would be working without the fulltext indexing provided by MySQL.

-- MySQL provides fast fulltext indexes.

-- MySQL is fast. It is generally as fast as PostgreSQL (or a little faster,
   as some people say), and it is much-much faster than SQLite. We had
   terrible performance issues with SQLite 3.3.5, partly because it
   always reopened the database files, partly because it failed to recognize
   the obviously proper index when executing SELECT queries.

-- MySQL is easy to set up with proper UTF-8 data support. PostgreSQL 8.1
   isn't (the whole cluster might have to be recreated with initdb(1)).
   MySQL is even easier to setup using pts-mysql-local.

-- A database with a mixture of UTF-8 strings (tags) and 8-bit binary
   strings (filenames) work like a charm in MySQL. No extra code is
   necessary for handling charcter set and collation issues if the schema
   is properly created, and SET NAMES ... is properly called. This should
   be the case with SQLite3, but problems might arise with PostgreSQL.

Why did we choose FUSE?

-- FUSE is safe during development (contrary to implementing our own kernel
   module or modifying e.g. Unionfs).

-- After installation (and kernel module loading), FUSE doesn't need root
   privileges.

-- FUSE is scriptable in Perl.

Why did we choose Perl?

-- Perl is powerful: it is easy to write simple programs in Perl, and it is
   not overcomplicated to write complicated programs. Ideal for
   implementing something from scratch, and also ideal for incremental
   software development while the specification changes.

-- FUSE is scriptable in Perl.

-- It is easy to add logging facilities to Perl scripts.

The reason why tagged files cannot span filesystem boundaries is that if
we store st_dev, and then the user changes the hard drive (i.e. by attaching
another drive in front of it), all st_dev values become bogus. A solution
better than spanning should be designed in further versions of movemetafs.

How to contribute
~~~~~~~~~~~~~~~~~
-- Integrate movemetafs.pl tagging and searching functionality to:

   -- your favourite file manager, e.g. Midnight Commander, KDE file
      manager, Gnome file manager;
   -- your favourite image viewer, e.g. qiv, xv;
   -- your favourite media player, e.g. MPlayer, VLC, Xine, Totemp;
   -- your favourite music player or organizer, e.g. XMMS;
   -- your favourite autindexer, e.g. Beagle

-- Create a web UI (with navigate, upload, download, tag, untag and search
   functionality).

Copyright and author
~~~~~~~~~~~~~~~~~~~~
movemetafs is free software, under the GNU GPL v2 or any newer version, at
your choice.

movemetafs is written by Péter Szabó <pts@fazekas.hu>. Download latest version
from the author's home page: http://www.inf.bme.hu/~pts/

How to report bugs
~~~~~~~~~~~~~~~~~~
If you experience something unexpected or counterintuitive when using
movemetafs.pl, try to reproduce it in the most simple configuration
possible, and send your report in e-mail to Péter Szabó <pts@fazekas.hu>.

Improvement possibilites
~~~~~~~~~~~~~~~~~~~~~~~~
!! configure: ft_max_word_len (global?): now it is 64 -- is it Unicode?
!! Dat: if you do not want _mangé_ to match with _mange_ (this example is in
   French), you have no choice but to use the BOOLEAN MODE with the double
   quote operator. This is the only way that MATCH() AGAINST() will make
   accent-sensitive matches.
!! Dat: A search for the phrase "let it be" won't find any record, not even
   records containing something like "The Beatles: Let It Be". According to
   the MySQL team, this is not a bug.
   I personally find it very counterintuitive to sometimes take short words
   into consideration for phrase searches, but only if there is at least one
   properly long word in the search phrase.
!! Dat: <50% threshold even without `IN NATURAL LANGUAGE MODE'
!! try: search without a stat (chdir(), stat(), ls(1))
!! try: chdir(), readdir()
!! verify: `_' in fulltext search separator
!! think: fulltext index needs MyISAM tables. Do they survive a system
   crash? No, because MyISAM is not journaling. So we should have a copy of
   the words in a regular InnoDB table, too.
!! easy: verify filesystem boundaries (done, test it)
!! what if the file os lost? (moved outside movemetafs)
!! feature: caching of recent shortname -> filename
!! feature: regenerate cache data
!! feature: possible as read-only as possible
!! get info: does the Fuse Perl module need locking? Is it serialized?
!! feature; if multiple filesystems are involved, how do we handle file
   moves?
!! feature: list metadata without getfattr(1)
!! feature: associate tags with directories
!! feature: non-symlink (but direct) results
!! feature: move from meta/tag/a to meta/tag/b (with symlinks)
!! feature: remember tags of removed files with SHA1 hash
!! refactor: reimplement in C
!! feature: option to have symlinks to the carrier
!! feature: database user, password etc.
!! doc: CREATE TABLE t (words TEXT COLLATE utf8_general_ci,
        FULLTEXT(words)) engine=MyISAM;
!! doc: SET NAMES 'utf8';
        SELECT * FROM t WHERE MATCH (words) AGAINST ('bar' IN BOOLEAN MODE);
!! feature: taxonomy with parent tags
!! feature: change short name to anything (without renaming)
# !! check for largefile support, 64-bit filesystem access (not possible in Perl?)
# !! keep filehandles open for FLUSH
!! feature: passing of POSIX extended attributes
!! feature: test mysql_auto_reconnect
!! examine: why are there so many GETATTR() etc. calls?
   How to cache? Which file manager to use?
!! feature: add relevance value to symlink names for sort() in ls(1)
!! feature: update (shorten) shortname when removing or moving away files
   with the same shortprincipal
!! cleanup: add `if $DEBUG'
!! feature: referential integrity (or cleanup): remove stale entries from
   `files'
!! examine: why do I get `mv: overwrite ...?' for the 2nd time if I issue
   this twice, within 1 second?
   mv /tmp/mp/root/proba/sub/one /tmp/mp/untag/foo
   This seems to be a FUSE bug...
!! feature: file change notification (for SHA1 hashes) with inotify,
   dnotify, snotify etc.
!! doc: performance on icy:
   $ time bash -c 'find -type f -print0 | xargs -0 -i mv {} /tmp/mp/tag/mytag'
   real    2m48.866s
   user    0m4.110s
   sys     0m7.420s
   $ ls | wc -l
   7684
!! doc: when reloading meta/tag/$TAGNAME in Midnight Commander, we get 3
   calls for each entry:
   GETATTR(/tag/jaypicz/001560-hr.jpg)
   READLINK(/tag/jaypicz/001560-hr.jpg)
   GETATTR(/root/E/pantyhose.z/jaypicz/jo/001560-hr.jpg)
!! doc: SUXX: how to find processes locking the stale FUSE filesystem?
!! measure: file transfer speed (once it is opened) Imp: symlink to real
   file?
!! measure: database size
!! feature: load a lot of data
!! feature: integrate recreate.sql to mmfs_fuse.pl
!! SET SESSION group_concat_max_len = 2000000000;
   SUXX: SELECT @@ft_max_word_len; -- ERROR 1193 (HY000): Unknown system variable 'ft_max_word_len'
   SELECT fs, ino, CONCAT(' ',GROUP_CONCAT(CONCAT(tag,IF(CHAR_LENGTH(tag)<4,IF(CHAR_LENGTH(tag)<3,IF(CHAR_LENGTH(tag)<2,'qqa','qb'),'k'),'q')) SEPARATOR ' '),' ') AS co FROM tags WHERE fs<>'' GROUP BY ino, fs HAVING co<>' jaypiczq ';
   INSERT INTO taggings (fs, ino, tags) SELECT fs, ino, CONCAT(' ',GROUP_CONCAT(CONCAT(tag,IF(CHAR_LENGTH(tag)<4,IF(CHAR_LENGTH(tag)<3,IF(CHAR_LENGTH(tag)<2,'qqa','qb'),'k'),'q')) ORDER BY tag SEPARATOR ' '),' ') FROM tags WHERE fs<>'' GROUP BY ino, fs ON DUPLICATE KEY UPDATE tags=VALUES(tags);
   SELECT * FROM taggings WHERE MATCH(tags) AGAINST('b\303\241llq');
!! report GROUP_CONCAT size bug
!! test: GROUP_CONCAT truncation
!! measure: search speed; Dat: /search/ results of 8000 files takes up to 0.3s to transfer -- slow?
!! feature: logical `or'
!! feature: symlink to large files
!! feature: check in large files in new FUSE
!! try: not possible to share /proc, because file sizes are `0'
!! doc: all command-line options
!! doc: how to use efficiently with Midnight Commander, qiv etc.
!! feature: migrate to a different filesystem based on `principal'
!! doc: tag regeneration while tagging, untagging and tag renaming
!! try: limits: many files, long tag names, long tagtxt
!! feature: check 2nd --root-prefix= (st_ino of /) on remount, warn
!! mv(1) first unlinks target before
   `mv /tmp/mp/tag/bar/\:5d53a\:F\:one /tmp/mp/tag/űrkikötő/',
   but what if we then get an `Operation not permitted'.

__END__
