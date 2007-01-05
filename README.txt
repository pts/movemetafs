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
   meta/tag/$TAGNAME or meta/untag/$TAGNAME folder
-- specify search query by changing to the invisible search/$QUERYSTRING
   folder
-- searching is fast, because it uses indexes
-- copy search results
-- after installation, movemetafs can be used on an existing filesystem
   instantly: there is no migration needed to make an existing filesystem usable with
   movemetafs: data doesn't have to be copied, moved, touched etc.
-- untagged files don't have any negative effect on the speed of movemetafs,
   even if the filesystem contains millions of files
-- nicely survives a system crash: non-cache data is stored in MySQL InnoDB
   tables (which use journaling), and even if the whole tag database is
   lost, the original filesystem remains usable without movemetafs
-- Stores tags in twice: once in a fulltext indexed column in a MyISAM
   table, and once in an InnoDB relational table. Ituses the fast MyISAM
   table for searches, and the InnoDB table for data recovery.

Current limitations:

-- cannot cross filesystem boundaries yet
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

Installation quickstart
~~~~~~~~~~~~~~~~~~~~~~~
!! this section isn't written properly

1. Download movemetafs.
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
try with U+00F7). Tag names are case-insensitive and accent-insensitive,
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

How to use
~~~~~~~~~~
After installation, mount the meta filesystem by running mmfs_fuse.pl
with the appropriate command-line arguments (for example, you have to
specify the path to the root folder of the carrier filesystem with
--carrier-root=). This script should remain running while you
want to access the filesystem, so it is advisable to start the script inside
screen(1). If mmfs_fuse.pl dies, you have to unmount the meta filesystem
with `fusermount -u /path/to/meta' before mounting it again. All these
operations can be done as a regular user (root is not necessary).

After starting mmfs_fuse.pl, the writable mirror view of the carrier
filesystem (--carrier-root=) becomes available as meta/root, with the
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
-- `getfattr -d meta/root/.../$FILENAME' displays all tags associated with
   the file in the `user.tags' field.

Besides meta/root, there are also some special folders in meta/, which
behave quite differently from regular filesystems:

-- Permissions and ownerships don't matter.
-- meta/tag
   -- meta/tag and its contents are not writable except for the
      operations listed below.
   -- Listing meta/tag yields all of the tags known by the system, as a
      directory.
   -- Listing `meta/tag/$TAGNAME' is equivalent to listing
      `meta/search/$TAGNAME' except for the relevance order,
      i.e. it lists all files having that tag.
   -- Creating a new directory in `meta/tag' creates a tag by that name to the
      system. Please note
      it is an error (Invalid argument) to add a non-UTF-8 tag name. Since
      tag names are case-insensitive and accent-insensitive, it is not
      possible (File exists) to add a tag `BaR' after `bar' has been added.
   -- Renaming a directory in `meta/tag/' renames the specified tag. This
      operation is quite slow: its speed is proportional to the number of
      files having that tag.
   -- Removing a directory in `meta/tag/' removes the specified tag from the
      system. This is not possible if there are files tagged with it.
   -- Moving a file from `root/...' (or `meta/tag/' or `meta/untag/'
      or `meta/search/' etc.) to
      `meta/tag/$TAGNAME' adds the tag named $TAGNAME to the specific file,
      and the file is _not_ removed from its original place (and its old
      tags are not changed either).
   -- It is not possible to add a tag to a file if the `meta/tag/$TAGNAME'
      directory doesn't exist (error: ENOENT). This is for protecting
      against typos.
   -- It is not possible to copy files into `meta/tag/' or create files
      there.
   -- Removing `meta/tag/$TAGNAME/$SHORTNAME' removes $TAGNAME from the
      file specified in $SHORTNAME.
-- meta/untag
   -- meta/untag behaves exactly like meta/tag, except when files are moved
      to `meta/untag/$TAGNAME', and except for `meta/tag/:all'.
   -- meta/untag and its contents are not writable except for the
      operations listed below.
   -- Listing meta/untag yields all of the tags known by the system, as a
      directory.
   -- Listing `meta/untag/$TAGNAME' is equivalent to listing
      `meta/search/$TAGNAME' except for the relevance order,
      i.e. it lists all files having that tag.
   -- Creating a new directory in `meta/untag' adds a tag by that name to the
      system. Please note
      it is an error (Invalid argument) to add a non-UTF-8 tag name. Since
      tag names are case-insensitive and accent-insensitive, it is not
      possible (File exists) to add a tag `BaR' after `bar' has been added.
   -- Renaming a directory in `meta/untag/' renames the specified tag. This
      operation is quite slow: its speed is proportional to the number of
      files having that tag.
   -- Removing a directory in `meta/untag/' removes the specified tag from the
      system. This is not possible if there are files tagged with it.
   -- Moving a file from `root/...' (or `meta/tag/' or `meta/untag/'
      or `meta/search/' etc.) to
      `meta/untag/$TAGNAME' removes the tag named $TAGNAME from the
      file, and the file is _not_ removed from its original place (and its old
      tags are not changed either). If all tags are removed from a file,
      the file is removed from the metadata store, and its principal name,
      checksums etc. are lost. Tags can be added at any later time.
   -- Removing `meta/untag/$TAGNAME/$SHORTNAME' removes $TAGNAME from the
      file specified in $SHORTNAME.
   -- It is not possible to copy files into `meta/untag/' or create files
      there.
   -- The tag is not removed, even if all files are removed from it.
   -- The folder `meta/untag/:all' appears to be an empty folder. When
      moving a file to this folder, all tags are removed from the file.
   -- Listing the folder `meta/untag/:all' yields all files known to
      movemetafs as symlinks.
   -- Removing `meta/untag/:all/$SHORTNAME' removes all tags from the
      file specified in $SHORTNAME.
-- meta/search
   -- meta/search appears to be an empty folder.
   -- meta/search and its contents are not writable.
   -- Listing (the invisible) meta/search/$QUERYSTRING will (re)run the search
      query specified in $QUERYSTRING, and list all resulting files as
      symlinks to the principal name of the file inside meta/root. See
      the section ``Search query strings'' for more information about query
      string syntax and the order of the files returned.

To search for files having a single tag only, you can use either
`meta/tag/$TAGNAME' or `meta/search/$TAGNAME'. To search for files having
both of two tags, use `meta/serach/$TAG1NAME $TAG2NAME' with the space.

Search query strings
~~~~~~~~~~~~~~~~~~~~
A search query string is a specification about tags. All files are returned
whose tags match the specification. For simple searches, files are returned
in decreasing order of relevance (not very important since most file
managers and ls(1) reorder the list).

MySQL fulltext search is used to find tags:

-- SELECT fs, ino WHERE MATCH(tags) AGAINST('$QUERYSTRING');
   This is used if $QUERYSTRING doesn't contain ASCII puctuation characters.

-- SELECT fs, ino WHERE MATCH(tags) AGAINST('$QUERYSTRING' IN BOOLEAN MODE);
   This is used if $QUERYSTRING contains ASCII puctuation characters.
   Please note that relevance is not much intuitive in boolean mode.

Read more about specifying MySQL fulltext search queries on
http://dev.mysql.com/doc/mysql/en/fulltext-search.html .

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
tag A or B in one query string.

Design decisions
~~~~~~~~~~~~~~~~
Search results (search/$QUERYSTRING/*) are symlinks.
!!

Improvement possibilites
~~~~~~~~~~~~~~~~~~~~~~~~
!! implement the spec
!! easy: keep a tag even if no files are associated with it: empty .fs
!! try: case insensitive tags
!! doc: no built-in way to search for files matching `A or B'
   !! feature: try: does MySQL optimize `MATCH() OR MATCH()'?
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
!! feature: auto boolean search when `+' or `-' is present
   Dat: Boolean searches do not automatically sort rows in order of decreasing
        relevance. You can see this from the preceding query result: The row with
        the highest relevance is the one that contains “MySQL” twice, but it is
        listed last, not first. (Also the relevance is not much accurate.)
!! symlink names, symlink targets
!! try: no <50% threshold when without `IN NATURAL LANGUAGE MODE'
!! try: search without a stat (chdir(), stat(), ls(1))
!! try: chdir(), readdir()
!! verify: _ and - in fulltext search separator
!! think: fulltext index needs MyISAM tables. Do they survive a system
   crash? No, because MyISAM is not journaling. So we should have a copy of
   the words in a regular InnoDB table, too.
!! easy: add qw to the end of words shorter than 4 (to avoid
   ft_min_word_length), and add q to each tag (to avoid stop words)
!! easy: only index regular files
!! easy: verify filesystem boundaries
!! easy: prevent removal of a multiple-hard-link file using its principal
   name
!! feature: verify st_dev (not spanning multiple filesystems)
!! UTF-8 etc. filenames
!! what if the file os lost? (moved outside movemetafs)
!! caching of recent mininame -> filename
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
!! feature: symlinks to the carrier
!! feature: database user, password etc.
!! doc: CREATE TABLE t (words TEXT COLLATE utf8_general_ci,
        FULLTEXT(words)) engine=MyISAM;
!! doc: SET NAMES 'utf8';
        SELECT * FROM t WHERE MATCH (words) AGAINST ('bar' IN BOOLEAN MODE);
!! feature: getfattr -d -> user.tags
!! feature: rebuild tag index
!! feature: root/untag/:all
!! feature: taxonomy with parent tags
!! feature: change short name
# !! check for largefile support, 64-bit filesystem access (not possible in Perl?)
# !! keep filehandles open for FLUSH
# !! implement POSIX extended attributes
!! feature: test mysql_auto_reconnect
!! examine: why are there so many GETATTR() etc. calls?
   How to cache? Which file manager to use?
!! feature: add relevance value to symlink names for sort() in ls(1)
!! feature: update (shorten) shortname when removing or moving away files
   with the same shortprincipal
!! cleanup: add `if $DEBUG'
!! feature: referential integrity (or cleanup): remove stale entries from
   `files'
!! feature: renaming tags with smart changes to table taggings
!! examine: why do I get `mv: overwrite ...?' for the 2nd time if I issue
   this twice, within 1 second?
   mv /tmp/mp/root/proba/sub/one /tmp/mp/untag/foo
   This seems to be a FUSE bug...
   

__END__
