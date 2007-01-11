README for movemetafs
by pts@fazekas.hu at Sun Jan  7 23:19:17 CET 2007

movemetafs is a searchable filesystem metadata store for Linux (with MySQL,
Perl and FUSE), which lets users tag local files (including image, video,
audio and text files) by simply moving the files to a special folder using
any file manager, and it also lets users find files by tags, using a boolean
search query. The original files (and their names) are kept intact.
movemetafs doesn't have its own user interface, but it is usable with any
file manager. movemetafs also lets users attach (unsearchable) textual
description to files.

In the name `movemetafs', `metafs' means filesystem metadata store, and
`move' refers to the most common way tags are added or removed: the user
moves the file to be acted on to the `meta/tag/$TAGNAME' or
`meta/untag/$TAGNAME' special folder. When the target folder is such a special
folder, the file is not removed from its original location (meta/root/**/*).

movemetafs is similar to LAFS (http://junk.nocrew.org/~stefan/lafs/)
(not tagji 1.1 by Manuel Arriaga). Most important differences:

-- movemetafs uses MySQL instead of PostgreSQL (benefits: speedup, easier
   installation with pts-mysql-local).
-- movemetafs doesn't require files to be explicitly added.
-- movemetafs cannot list all untagged files quickly.
-- movemetafs is written in Perl, so it is quite easy to extend and try
   out new features.
-- movemetafs continues to work when files are renamed.
-- movemetafs works with files with more than one hard link.

Features of movemetafs:

-- Use any file manager to tag files: move the file to the
   `meta/tag/$TAGNAME' or `meta/tagged/$TAGNAME' folder. The file is not
   removed from its original folder.
-- Use any file manager to untag files: move the file to the
   `meta/untag/$TAGNAME'. The file is not
   removed from its original folder.
-- Specify search query by changing to the invisible
   `meta/search/$QUERYSTRING' folder. Results are symbolic links into
   `meta/root'.
-- If you want to search for only a single tag, list the folder
   `meta/tagged/$TAGNAME'. Results are symbolic links into `meta/root'.
-- Alternatively, you untag a file by removing the symlink
   `meta/tagged/$TAGNAME/$FILENAME'.
-- Alternatively, use POSIX extended attributes to retrieve (or even set)
   the tags associated to a file.
-- Attach textual descriptions to files, and read the description once the
   file is found.
-- Use POSIX extended attributes to get and set the textual description of
   a file.
-- Create a recursive POSIX extended attribute dump (of tags and
   descriptions) from the database very quickly.
-- Restore the created POSIX extended attribute dump with
   `setfattr --restore'.
-- Use versatile search query syntax (MySQL fulltext search) with the
   possiblity of boolean search (i.e. searching for files matching a
   combination of tags).
-- Copy search results to make backups or to create collections.
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
-- Treats file names as opaque 8-bit strings, thus it works with any
   filesystem character set, even when character sets are mixed in the
   middle of the filename.
-- Uses UTF-8 for tag names and descriptions.
-- Filenames in search results are automatically made unique when necessary.
-- Following the Unix filesystem design, files with multiple hard links
   share a commond description and a common set of tags. If tags or
   the description are changed on one name, the changes also apply to other
   names, too.

Current limitations:

-- cannot cross filesystem boundaries. This means that tags cannot be added
   to (or removed from) files not on the carrier filesystem (--root-prefix=).
   No other restrictions are present when accessing `meta/root'.
-- alpha software, ready for local use only
-- cannot cross filesystem boundaries
-- doesn't survive a mkfs + rsync migration
-- tags are lost when the file is copied (use md5sums?)
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
-- FUSE is a little slower than other layers such as Unionfs or Relayfs
-- Perl Fuse.pm is a little slower than writing a Fuse module in C
-- no logic structuring (such as taxonomy, thesaurus or ontology) and
   inference
-- For files with multiple (hard) links, symlinks in search results point to
   only one of filenames (usually the oldest) -- the other filenames are not
   stored by movemetafs.
-- For files with multiple (hard) links, the principal name cannot be
   easily removed. (But it can be changed.)
-- Original POSIX extended attributes and ACLs are not mirrorred.
-- Searching is much faster than tagging and untagging.
-- Tags cannot be multiple levels deep (i.e. contain `/').
-- File descriptions are not searchable.

Dependencies (install them in this order):

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
   configuration if you use pts-mysql-local). movemetafs is being tested
   with MySQL server 5.1. Please let me know if it
   doesn't work with 5.0 or 4.1. Earlier versions of MySQL are not supported
   by movemetafs.
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
5. Textual description is added for some files.
6. Searches are performed based on tag names. Search results are presented
   as symlinks to normal files. on the filesystem. The name of the symlink
   is similar to the name of the original files (but ambiguities are
   resolved).
7. Tag names and descriptionsa re retrieved as POSIX extended
   attributes (getfattr(1), `getfattr -d -e text -- $FILENAME').
8. As an overall effect, with movemetafs files are much easier to find, and
   it is easy to make file collection based on a specific theme.

To organize your images, GQview (>=2.0, we tried 2.1.5) is recommended.
Pressing Ctrk-<K> in GQview lets you enter keywords and a comment for the
image. In our movemetafs terminology, `keyword' is named tag, and `comment'
is named description. By default, GQview stores metadata (i.e. tags and the
description) in a *.meta file (near the image file or in
~/.gqview/metadata). We have prepared a patch to GQview-2.1.5, which will
make GQview store metadata in the movemetafs metadata store for images
inside `meta/root'.  This makes GQview a very nice and powerful user
interface for movemetafs when managing images.

How to install
~~~~~~~~~~~~~~
All steps (except where indicated) should be done your regular, normal user,
not as root.

1. Download movemetafs from http://www.inf.bme.hu/~pts/ or
   http://freshmeat.net/projects/movemetafs/
2. Install the dependencies (see above).
3. Load the `fuse' kernel module. If not found, compile or install it, and
   reboot if necessary. Test with `grep "^fuse " /proc/modules'.
4. Extract the distribution tarball and chdir() to the folder just extracted.
   You will be running `mmfs_fuse.pl' from here.
5. Copy the file `movemetafs.conf.ex' to `movemetafs.conf'.
6. Start the MySQL database server.
7. Connect to your MySQL server with the mysql(1) client utility. Connect
   with a user having the privileges of creating databases, creating users
   and granting rights. Usually `mysql --user=root --password' should do the
   trick. On success, exit from `mysql'.
8. Change the string `put_password_here' in both `movemetafs.sql' and
   `recreate.sql' to a more secret password, which will be used by
   `mmfs_fuser.pl' for connecting to the MySQL server.
9. Initialize the MySQL database using `recreate.sql'. Use the mysql(1)
   command that worked in step 6, like this:

     $ mysql --user=root --password <recreate.sql

   You shouldn't get any errors.
   
   This creates the database `momvemetafs', the tables and other schema
   elements, the MySQL user `movemetafs_rw', and the appropriate rights for
   the user to access the database.

   This has to be done only once on the same machine, because it destroys
   all metadata known to movemetafs.
10. Edit `movemetafs.conf'. The defaults are almost always correct, except
    for the key `db.dsn', which should point to the MySQL server. Examples:

      db.dsn: dbi:mysql:database=movemetafs:mysql_socket=/var/run/mysql.sock
      db.dsn: dbi:mysql:database=movemetafs:host=localhost;port=3306

    You have already changed the password in `db.auth' above:

      db.auth: some_hard_to_guess_password

    Read more about the available options in section ``Statup
    configuration''.
11. Run `mmfs_fuse.pl --test-db'. It shouldn't print any errors, but
    `Database connect OK.' and `Tables OK.'.
12. If you want to try movemetafs right now, continue in section
    ``How to use''.

Basic concepts: carrier and meta filesystems etc.
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
There are two filesystems: the carrier and the meta. The carrier filesystem
is the one that stores the actual files (and directory structure).
As of version 0.05, it doesn't matter how many real mount points (and
different st_dev values) the carrier has -- it can span multiple filesystem.
(But please read more about the rare unsafe operations on filesystems
in the section ``Migration''.)

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
tags, `untag' for removing tags, `tagged' for displaying and manipulating
tags, and `search' for searching. All
functionality of these special folders can be used from any file manager
(recommended: Midnight Commander), the exact way how to do it is documented
later.

movemetafs stores metadata (== metainformation; such as which file has what
tags associated to it) in a MySQL database, which can be located anywhere:
any folder on the local machine, or even on a remote host. A remote host is
not recommended, though, because network transmission might be slow.

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
when it was last renamed). For safety (and operability) reasons, movemetafs
gives the EPERM error when you attempt to remove (unlink) the principal name
of a file with multiple hard links. To remove such a name A, locate another
name B first (might involve a slow find(1) with `-inum ...' on the carrier),
move B to `meta/adm/fixprincipal', then remove A. (Alternatively of moving
B, you can rename B to B1, and rename B1 back to B.)

Short name: each tagged file has a short name, which is displayed as the
name of the symlink in search results. The short name is generated from the
principal name (keeping only the last path component, the filename),
shortening it to 255 bytes when necessary, and adding a unique prefix
of the form `:<ino-hex>:<fs>:' if multiple files have the same shortened
principal, shortened again if necessary.

No restrictions are present when accessing files with different st_dev value
in `meta/root'. In versions before 0.05, attempts to tag or untag files with
a different st_dev value (than of `root.prefix') resulted in a `Remote I/O
error' (EREMOTEIO). Now this restriction is removed, but please read section
``Migration'' about possibly unsafe filesystem operatios.

Description: Each file has a textual description associated with it, which
can be used to add additional information (such as the story depicted on the
media file or the story of the file creation itself). The description is not
stored on the real filesytem, but in the MySQL database. The
description can be read and written using the `user.mmfs.description' POSIX
extended attribute. Each file has an empty description by default. The
maximum description length is 65535 bytes (because setfattr(1) cannot pass
longer POSIX extended attributes to FUSE Perl scripts -- the limit on the
size of MySQL `text' fields is much larger).

Character sets (== encodings) and collations
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
movemetafs handles filenames as opaque 8-bit strings (thus filenames can be
in any character set, or in a mixture of character sets). All characters are
allowed in filenames (except for `/' and "\0", of course, which are not
allowed in any UNIX filename). Maximum filename length (checked by both
MySQL and Linux) is 255 bytes.

movemetafs refuses to add tags with a name not in UTF-8. The software makes
no attempt to convert to UTF-8 from a local character set specified by the
locale (LC_CTYPE etc.) -- because this information is not available to FUSE.
MySQL `COLLATE utf8_general_ci' is used for sorting and comparing tags
(which is case-insensitive, accent-insensitive and
trailing-space-insensitive), see above.

movemetafs refuses to set descriptions not in UTF-8. All characters,
including "\0" are allowed. To add a description containing "\0", create
an attribute dump file attr_dump:

  # file: meta/root/dir/file
  user.mmfs.description="a\000\142"

Then restore the dump:

  $ setfattr --restore=attr_dump

You can verify that all 3 bytes are present:

  $ getfattr -d -e text -- meta/root/dir/file
  # file: meta/root/dir/file
  user.mmfs.description="a\000b"

Startup configuration
~~~~~~~~~~~~~~~~~~~~~
movemetafs can be configured using command-line options and/or configuration
file entries. The configuration file is `movemetafs.conf' in the folder
`mmfs_fuse.p'l is started (except when the
`--config-file=<file>' command-line option is present). No other search is
done for the configuration file.

Configuration entries are key--value pairs. Keys are case
sensitive. The characters `-' and `_' are converted to `.' in keys when the
configuration entry is read. Leading and trailing whitespaces are ignored in
lines. A line starting with a `#' (possibly after whitespace) is ignored.
Other lines must be in the form `<key>=<value>' or `<key>="<quoted-value>"'.
Whitespace around `=' is ignored. `:' is also accepted in place of `='.
Quoted values are like C string, the following escapes are recognized:
\000 .. \377 (octal), \n, \t, \f, \b (backspace), \a, \e, \v and \r.
Escaping other characters is also OK (e.g. `\\' and `\"'). Example entries:

  newline = "\n"
  db.auth =  a password with four spaces
  db.auth = ""
  # Cannot put this comment at the end of the previous line.

Configuration entries can be specified in the command-line, too, prefixed by
`--'. For example, `--db-auth=my_password'. Entries specified in the command
line override those in the configuration file. Some command-line options
have no equivalent in the configuration file:

-- --config-file=<file>: set configuration file name
-- --version: print movemetafs version number (and some messages) and exit
-- --help: print (the lack of) help and exit
-- --test-db: perform some simple tests on the database (can we connect? do
   we have all the tables with all the necessary fields? can we make
   modifications?)
-- --quiet: decrease the value of `verbose.level' by 1
-- --verbose: increase the value of `verbose.level' by 1

Usually there is no need to override the defaults entries, except for
the database connection parameters (`db.*'), most importantly `db.dsn'.
Other useful entries are `verbose.level' and `root.prefix'.

The most important configuration entries for movemetafs:

-- db.dsn (mandatory, no default): Perl DBI data source name pointing to the
   MySQL server. See more in `perldoc DBD::mysql'.
-- db.username (default: `root'): MySQL user name (usually `movemetafs_rw').
-- db.auth (default: empty): MySQL user password.
-- db.onconnect.1 ... db.onconnect.9 (default: missing): SQL statements to
   be executed upon connecting to the database. Usuually none.
-- default.fs (default: `F'): default value to be put to the `fs' columns of
   various tables. Has only historical significance. Should be quite short.
-- read.only.p (default: `0'): a boolean; if true, the meta filesystem
   becomes read-only.
-- enable.purgeallmeta.p (default: `0'): a boolean; if true, the dangerous
   `meta/adm/prugeallmeta' functionality is enabled. This is dangerous,
   because it can be used to purge all tags and descriptions ever known
   in one step, without confirmation.
-- verbose.level (default: `1'): integer; controls the amount of debug
   messages printed by `mmfs_fuse.pl'. Use `1' to get all the
   debug messages, use `0' to suppress most (and make operation a little
   faster).
-- mount.point (mandatory, default is "$ENV{HOME}/mmfs"):
   folder writable by you to which the
   meta filesystem is mounted, i.e. `meta/root' will be `<dir>/root' if
   `mount.point=<dir>'. You may have to create this folder manually before
   starting `mmfs_fuse.pl'. Because of how FUSE works, other users on
   the system (`root' included) won't be able to see into this folder once the
   meta filesystem is mounted.
-- root.prefix (default: '/'): the carrier filesystem folder, this will
   be visible as `meta/root'. Can be absolute or relative (to the current
   folder of the `mmfs_fuse.pl' program invocation).

To find out more configuration entries, please read `mmfs_fuse.pl'
(search for `%config_default' and `config_process_option').

How to use
~~~~~~~~~~
Startup steps:

1. Install movemetafs if you haven't done so (read details in section
   ``How to install''.
2. Mount the carrier filesystem(s) (on which the files you want to tag
   reside).
3. Start the MySQL database server.
4. Ensure that the `fuse' kernel module is loaded. This has to be done as
   root.
5. Start `mmfs_fuse.pl' with the appropriate configuration, as documented in
   the section ``Startup configuration''. This mounts the meta filesystem.

   Please remember the command-line options (especially --root-prefix=),
   because finding tagged files might not work if some crucial options are
   different when remounting it later.

The `mmfs_fuse.pl' script should remain running while you want to access the
filesystem, so it is recommended to start the script inside screen(1). If
mmfs_fuse.pl dies, you have to unmount the meta filesystem with `fusermount
-u /path/to/meta' before mounting it again. All these operations can be done
as a regular user (root is not necessary).

The folders of the meta filesystem are designed to be as intuitive as
possible:

-- Use `meta/root' to browse (or even modify) the carrier filesystem.
   Be careful to do write operations here (and not on the carrier directly,
   even when the meta filesystem is not mounted).
-- Use `meta/tag' to add and remove tags.
-- Move a file to `meta/tag/$TAGNAME' to add a tag to it.
-- Move a file to `meta/untag/$TAGNAME' to remove a tag from it.
-- Use `meta/tagged' to list files associated to a particular tag, and
   the tag from some of those files.
-- Use `meta/search' to search for files matching one or more tags
   (all of them, any of them, or a combination of them -- the full power
   of MySQL boolean fulltext search is at your disposal).

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

-- (Safe only in meta filesystem.)
   If a file is moved (or, equivalently, renamed) inside meta/root, its
   principal name is changed to the new name. Most of the files have link
   count of 1, thus this should be the correct behaviour. Renaming can be
   used to deliberately change the principal name of a file with multiple
   hard links. See also ``Principal name''.
-- (Safe only in meta filesystem.)
   If a file has multiple hard links, its principal name is not allowed
   to be removed (Operation not permitted, EPERM). This a a safety feature
   that prevents the `files.principal' column getting stale. See more
   in ``Principal name''.
-- (Safe only in meta filesystem.)
   If a last link to a file is removed (or a folder is removed), movemetafs
   removes all tags associated with it and its description.
-- `getfattr -d -e text meta/root/.../$FILENAME' displays all tags
   associated with the file in the `user.mmfs.tags' attribute (sorted and joined
   by a single space) and the file's description in the `user.mmfs.description'
   attribute. If no tags are associated with the file, `user.mmfs.tags' is empty.
   If no description has been set for the file, `user.mmfs.description' is empty.

   Each file (and other node) in `meta/root' (but not `meta/root' itself)
   has the attribute `user.mmfs.realnode' with value `1'. All other nodes have
   the attribute `user.mmfs.fakenode' with value `1'.
-- `setfattr -n user.mmfs.tags -v "$TAGS" $meta/root/.../$FILENAME' can be used
   to set the tags associated with the file. All tags specified in the
   whitespace-separated tag list $TAGS get added to $FILENAME, and all
   other tags get removed from it. If $TAGS is
   empty, you have to omit `-v'.
   
   Please note that it is not possible add unknown tags via
   `user.mmfs.tags' (`Cannot assign requested address' will be reported).
   However, it is possible to bulk add tags using
   `meta/adm/addtags', and using `setfattr --restore' after that.
   
   Using `user.mmfs.tags' is not the recommended method of adding tags to a
   file (because it might also remove tags); to do so, move the file from
   `meta/root/...' to `meta/tag/$TAGNAME/'.
-- `setfattr -n user.mmfs.description -v "$DESCRIPTION" $meta/root/.../$FILENAME'
   can be used to set the file's description to $DESCRIPTION. Please note
   that $DESCRIPTION must be specified in UTF-8. Please note that if
   $DESCRIPTION is empty, you have to omit the `-v' option of `setfattr'.
-- POSIX extended attributes cannot be removed (e.g. with `setfattr -x')
   in the meta filesystem. An attempt to remove an attribute is equivalent
   to setting its value to the empty string.
-- Attributes cannot be modified, except for `user.mmfs.description' and
   `user.mmfs.tags'. An attempt to modify another attribute succeeds if the old
   and new values are the same, and returns `Operation not permitted'
   otherwise.
-- There is also the write-only attribute `user.mmfs.tags.tag' to add tags
   (in the value, separated by whitespace) and `user.mmfs.tags.untag' to
   remove tags.

Some of the operations above are markes with `Safe only in meta filesystem.'
This means that these operations should not be performed on the carrier
filesystem directly (even when the meta filesystem is not mounted) on files
having tags or a nonempty description. That's because these operations they
might cause a mismatch between the files and their metadata if performed
on the carrier filesystem without the meta filesystem being notified.

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
   -- Creating a new folder in `meta/tag' creates a tag by that name in the
      system. Please note
      it is an error (Invalid argument) to add a non-UTF-8 tag name. Since
      tag names are case-insensitive and accent-insensitive, it is not
      possible (File exists) to add a tag `BaR' after `bar' has been added.
   -- Removing a folder in `meta/tag/' removes the specified tag from the
      system. This is not possible (Directory not empty, ENOTEMPTY)
      if there are files tagged with it. Tag removal never happens
      automatically.
   -- Listing `meta/tag/$TAGNAME' yields an empty folder. This is now so
      because having symlinks to tagged files here (which were there in
      movemetafs-0.02 and earlier, and which is now returned by
      `meta/tagged/$TAGNAME) caused problems when tagging by file moving:
      some file managers (e.g. mv(1) and Midnight Commander) tried to be
      smart and stat() the target dir, and report the annoying message to
      the user that the file to be tagged already existed.
   -- Moving a file from `meta/root/...' (or `meta/tag/' or `meta/untag/'
      or `meta/tagged/' or `meta/search/' etc.) to
      `meta/tag/$TAGNAME' adds the tag named $TAGNAME to the specific file,
      and the file is _not_ removed from its original place (and its old
      tags are not changed either). In fact, this is the preferred method
      of adding tags.
      
      Please note that moving files from the carrier
      into `meta/tag/.../' won't ever work -- move files from
      `meta/root/...' instead.
   
      Please note that it is possible to add tags only to regular files.
      Thus directories, sockets, pipes and device special nodes are not
      allowed to be moved to `meta/tag/$TAGNAME' (error message:
      Operation not permitted). This is a quite artificial limitation in
      movemetafs, so it might get removed in the future.
      
      It is not possible to add a tag to a file if the `meta/tag/$TAGNAME'
      directory doesn't exist (error: ENOENT). This is for protecting
      against typos in tag names. (And it is also imposed by the FUSE
      architecture.)
   -- It is not possible to copy files into `meta/tag/' or to create files
      there.
   -- Renaming `meta/tag/$OLDTAGNAME' to `meta/tag/$NEWTAGNAME' renames the
      specified tag. The amount of time needed is proportional to the number
      of files $OLDTAGNAME is associated to. Renaming works with
      `meta/untag' or `meta/tagged' in place of `meta/tag' for both folder
      names. If $NEWTAGNAME already exists, tags $OLDTAGNAME and $NEWTAGNAME
      are merged to $NEWTAGNAME for each file having either of them. Some
      utilities such as GNU mv(1) try to be smart and move $OLDTAGNAME
      inside `meta/tag/$NEWTAGNAME' if the latter exists (as a directory).
      This can be circumvented by adding spaces to the front or end of
      $NEWTAGNAME, for example `mv meta/tag/old "meta/tag/existing "'.
-- meta/untag
   -- `meta/untag' behaves exactly like `meta/tag', except when files are
      moved to `meta/untag/$TAGNAME', and except for `meta/tag/:all'.
   -- `meta/untag' and its contents are not writable except for the
      operations listed below.
   -- Listing `meta/untag' yields all of the tags known by the system, each as
      a directory.
   -- Creating a new folder in `meta/untag' adds a tag by that name in the
      system. Please note
      it is an error (Invalid argument) to add a non-UTF-8 tag name. Since
      tag names are case-insensitive and accent-insensitive, it is not
      possible (File exists) to add a tag `BaR' after `bar' has been added.
   -- Removing a folder `meta/untag/' removes the specified tag from the
      system. This is not possible (Directory not empty, ENOTEMPTY)
      if there are files tagged with it. Tag removal never happens
      automatically.
   -- Listing `meta/untag/$TAGNAME' yields an empty folder.
   -- Moving a file from `root/...' (or `meta/tag/' or `meta/untag/'
      or `meta/search/' etc.) to
      `meta/untag/$TAGNAME' removes the tag named $TAGNAME from the
      file, and the file is _not_ removed from its original place (and its old
      tags are not changed either). If all tags are removed from a file,
      the file is removed from the metadata store, and its principal name,
      checksums etc. are lost. Tags can be added at any later time to that
      file.
   -- It is not possible to copy files into `meta/untag/' or to create files
      there.
   -- The tag is not removed, even if all files are removed from it.
   -- The folder `meta/untag/:all' appears to be an empty folder. When
      moving a file to this folder, all tags are removed from the file.
   -- Renaming `meta/untag/$OLDTAGNAME' to `meta/untag/$NEWTAGNAME' renames
      the specified tag. See more about renaming tags under `meta/tag'.
-- meta/tagged
   -- `meta/tagged' behaves like `meta/tag' with the exception that
      `meta/tagged/$TAGNAME' is not always empty.
   -- Listing `meta/tag/$TAGNAME' yields the list of all files having
      that tag, as symlinks (with short name). This is almost equivalent
      to `meta/search/+$TAGNAME' except that `meta/search' returns
      results in decreasing order of relevance, and `meta/tagged' returns
      results in no particular order.
   -- Removing `meta/tagged/$TAGNAME/$SHORTNAME' removes $TAGNAME from the
      file specified by $SHORTNAME.
   -- Moving `meta/tagged/$TAGNAME/$SHORTNAME' to `meta/tag/$ANOTHERTAGNAME/'
      doesn't remove $TAGNAME from the file specified by $SHORTNAME, but it
      adds $ANOTHERTAGNAME to the file.
   -- Moving `meta/tagged/$TAGNAME/$SHORTNAME' to `meta/untag/$ANOTHERTAGNAME/'
      removes $ANOTHERTAGNAME from the file specified by $SHORTNAME, but it
      doesn't remove $SHORTNAME.
   -- As a legacy solution, if moving a file to `meta/tagged/$TAGNAME/'
      doesn't work (e.g. with mv(1):
      `cannot overwrite non-directory') even when forcing it, try
      moving to `meta/tag/$TAGNAME/::' instead of `meta/tag/$TAGNAME'.
      However, you shouldn't be moving files to `meta/tagged/$TAGNAME/'
      anyway -- it is safest to move the file to `meta/tag/$TAGNAME'
      instead.
   -- Listing the folder `meta/untag/:all' yields all files having at least
      one tag or a nonempty description.
   -- Removing `meta/untag/:all/$SHORTNAME' removes all tags from the
      file specified in $SHORTNAME.
-- meta/search
   -- `meta/search' appears to be an empty folder.
   -- `meta/search' and its contents are not writable.
   -- Listing (the invisible) `meta/search/$QUERYSTRING' will (re)run the
      search query specified in $QUERYSTRING, and list all resulting files as
      symlinks to the principal name of the file inside meta/root. See
      the section ``Search query strings'' for more information about query
      string syntax and the order of the files returned.
   -- `meta/search/$QUERYSTRING' uses the MySQL table `taggings', while
      `meta/tag/$TAGNAME' uses the table `tags'. Should any mismatch arise,
      `mkdir meta/repair_taggings' regenerates `taggings' from `tags'.
-- meta/adm
   -- The folder `meta/adm' appears to contain a few empty folders.
   -- `meta/adm' can be used to issue administrative and recovery commands
      to movemetafs.
   -- If the folder `meta/adm/reload_fss' is attempted to be created,
      movemetafs reloads the `fss' table into its local cache, and
      the operation returns `No such file or directory' on success.
   -- If the folder `meta/adm/repair_taggings' is attempted to be created,
      movemetafs regenerates the `taggings' table from the `tags' table, and
      the operation returns `No such file or directory' on success. This
      regeneration can be quite slow, since the time needed is proprtional
      to the number of tags in the system (with multiplicity for each file
      they are associted to).
   -- The folder `meta/adm/fixprincipal' appears to be empty. If a file
      is moved here from `meta/root', the file is kept on its original
      place, but the principal name (of its inode) is changed to the
      the source name in the rename. This is a useful operation when a
      tagged file is somehow lost (for example, it has been renamed directly
      on the carrier filesystem), or if it is desired to change the
      principal name of a tagged file with multiple hard links. Read more
      in ``Principal name''.
   -- The folder `meta/adm/fixunlink' appears to be empty. If a file
      is moved here from `meta/root', all metadata movemetafs knows about
      the file and its hard links (including tags, description and principal)
      is forgotten. If the specified name is a principal name of a file
      (with any inode number), all information is removed
      from that file, too.

      Please note that this tool is a little dangerous since it
      removes metadata.
   -- `meta/adm/fixunlinkino:<dev>,<ino>' (where <dev> is a hexadecimal
      st_dev number and <ino> is a hexadecimal st_ino number of the same
      file) is a missing directory. When attemted to be created, all
      metadata movemetafs knows about the file (speficied by <dev>,<ino>)
      and its hard links is forgotten (and `No such file or directory'
      is returned). This tool can be used to forcibly remove stale inodes
      from the database.
   -- `meta/adm/purgeallmeta' is a missing directory. When it is attempted
      to be created, all tags and descriptions in the metadata store are
      permanently erased (and `No such file or directory' is returned).
      That is, the tables `files', `tags' and `taggings' are
      truncated to zero. This is a very dangerous operation, and it is
      disabled by default, unless the `enable.purgeallmeta.p' configuration
      entry is set to true (e.g. `1'). `meta/adm/purgeallmeta' can be useful
      just before a recursive attribute restore (`setfattr --restore').
   -- `meta/adm/dumpattr' is a missing file. If a file
      is moved over it from `meta/root', the file is kept in its original
      place, but its contents will be overwritten by a POSIX extended
      attribute dump file, which contains all files with tags and
      descriptions known in the movemetafs metadata store. Only metadata
      attributes managed by movemetafs are dumped (i.e.
      `user.mmfs.description' and `user.mmfs.tags'). This is a
      reasonably fast operation, because only the database is consulted
      (the carrier filesystem isn't).
      
      Example for dumping:
      
        $ touch meta/root/user.mmfs.dump
        $ mv meta/root/user.mmfs.dump meta/adm/dumpattr
      
      Dumping is almost equivalently to:
      
        $ (cd meta/root; getfattr -R -d -e text . >user.mmfs.dump)
        
      Important differences between `getfattr -R' and `meta/adm/dumpattr':
      
      -- `getfattr -R' examines all files recursively, `meta/adm/dumpattr'
         examines only the metadata database, which contain only tagged
         files (and files with nonempty description). Thus `getfattr -R' is
         much slower.
      -- `getfattr -R' dumps the unnecessary `user.mmfs.realnode' attribute,
         `meta/adm/dumpattr' doesn't.
      -- The two dump methods quote non-ASCII and non-printable characters
         differently, `meta/adm/dumpattr' is more careful.
      
      Example of restoring the dump:

        $ mv meta/root/user.mmfs.dump meta/adm/addtags      
        $ (cd meta/root; setfattr --restore=user.mmfs.dump)
        
      Please note that restoring is much slower (about a factor of 100??)
      than dumping.
        
      Dumping can be used to migrate the filesystem between machines and
      filesystems. Read more about migration in the section ``Migration''.
      
      Dumping and restoring are locale-independent operations.
      in ``Principal name''.
   -- `meta/adm/addtags' is a missing file. If a file
      is moved over it from `meta/root', the file is kept in its original
      place, but all tags it contains would be added (like
      `mkdir meta/tag/$TAGNAME'). This is useful before restoring a
      POSIX extended attribute dump (otherwise setfattr(1) will report
      `Cannot assign requested address').
      
      Each line of the file is processed separately. Lines starting with `#'
      (possibly preceded by whitespace) are ignored. If the line starts with
      `user.mmfs.tags="', it is treated as a `getfattr -d -e text' dump
      line, otherwise the line is treated as a whitespace-separated list of
      tags. Lines with syntax error are reported to STDERR (of mmfs_fuse.pl)
      and are ignored.
   -- All other write operations in `meta/adm'
      fail with `Operation not permitted'.

If you get `Transport endpoint is not connected' for a file operation in
meta/, this means mmfs_fuse.pl has crashed. This usually means there is a
software bug in movemetafs, so please report it (see section ``How to report
bugs''). To recover from a crash, just exit from all applications using
meta/ (too bad that `fuser -m meta' won't show the PIDs -- please report
this as a bug to the FUSE developers), umount meta/ with `fusermount -u
meta', and after exiting, restart `mmfs_fuse.pl'. (Upon startup,
mmfs_fuse.pl runs `fusermount -u meta' automatically. Due to a limitation in
the Fuse Perl module, it cannot do the same upon exit.)

mmfs_fuse.pl should run forever without Perl error and warning messages,
without eating up more and more memory, and without becoming unresponsive.
If you experience something otherwise, please report it as a bug.

Since mmfs_fuse.pl is single-threaded, only 1 filesystem operation is
possible at a time: each operation has to wait until other pending oparions
finish. This can lead to increased blocking times if multiple processes try
to access the meta filesystem simultaneously.

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

Please note that a query with only negative terms (such as `-foo -bar')
doesn't match any files. (This is a MySQL fulltext search rule.)

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

Migration
~~~~~~~~~
Since movemetafs uses not only the file name, but also the device number
(st_dev) and the inode number (st_ino) on the carrier filesystem to identify
files, problems might arise when st_dev or st_ino change.

st_dev changes

-- when (part of) the filesystem is moved to another partition,
-- or the data is copied (migrated) to another filesystem or another machine;
-- or the device is connected under a different name (e.g. the hard
   drive is recognized as /dev/sdb instead of /dev/sda);
-- or the filesystem is rebuilt (e.g. the system is restored from a .tar.gz
   backup).

st_ino changes

-- when the data is copied (migrated) to another filesystem or another
   machine;
-- or the filesystem is rebuilt (e.g. the system is restored from a .tar.gz
   backup);
-- or a file is moved in a `copy; delete' sequence.

Extended attribute migration can be a solution in those cases.
(It might succeed even if it is done late, after st_dev or st_ino has
changed.) During extended attribute migration, st_dev and st_ino don't
matter, because attribute dump and restore is based on file name (more
precisely: principal name).

The steps:

1. Dump the attributes using `root/adm/dumpattr'.
2. Copy everything recursively to the target filesystem, without copying
   extended attributes.
3. Copy the attribute dump to the target filesystem.
4. Remove all movemetafs metadata on the target system.
5. Restore the attribute dump on the target system.

Example of migration with rsync(1) (simplified):

  $ touch meta/root/user.mmfs.dump
  $ mv meta/root/user.mmfs.dump meta/adm/dumpattr
  $ rsync -aHvz meta/root/ targethost:carrier/
  $ ssh target 'screen mmfs_fuse.pl --enable-purgeallmeta-p=1'
  $ ssh targethost '
      mkdir meta/adm/purgeallmeta
      mv meta/root/user.mmfs.dump meta/adm/addtags
      (cd meta/root && setfattr --restore=user.mmfs.dump)'

Please note that the `-H' option of `rsync' is important -- otherwise hard
links wouldn't have been preserved.

Changing mount points and recovery from stale symlinks
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
!! write this

FAQ, troubleshooting
~~~~~~~~~~~~~~~~~~~~
Q1. `meta/search' doesn't find some of the files I've tagged.
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Try to diagnose with `meta/tagged' first (see also question Q2). If it works
in `meta/tagged', verify that your search query string is correct (read more
in section ``Search query strings''). If your search query string is
correct, try running `mkdir meta/adm/repair_taggings' and try the search
again.

Q2. `meta/tagged/$TAGNAME' doesn't contain a file I've tagged.
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Look at the files `meta/tagged/$TAGNAME/:*:*:*'. Your file might be there.

If you've tagged in GQview, are you sure that you saved the keywords before
quitting?

If `meta/tagged/$TAGNAME' contains a similarly named file with a stale
symlink, you might have renamed the file outside movemetafs's control, or
you might have changed mount points. Locating the file yourself and moving
it to `meta/adm/fixprincipal' might help. If a lot of files are affcted,
see section ``Changing mount points and recovery from stale symlinks''.

Q3. `getfattr -d' reports an empty user.mmfs.description, but it shouldn't.
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
Try solutions for question Q2.

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

Since searching should be faster than tagging, the calculation of
short names is done when a file is tagged, untagged (or its description
is changed etc.).

The reason why the `user.mmfs.' prefix was chosen for the POSIX extended
attributes was that FUSE works with `user.' only (other attributes are not
returned to the process), but `user.' is too broad and generic.

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

How to contribute
~~~~~~~~~~~~~~~~~
-- Integrate movemetafs.pl tagging and searching functionality to:

   -- your favourite file manager, e.g. Midnight Commander, KDE file
      manager, Gnome file manager;
   -- your favourite image viewer, e.g. GQview, qiv, xv;
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
!! feature: tag alias symlinks
!! test: rename across mount points with GNU mv(1). GNU mv(1) doesn't seem
   to preserve extended attributes
!! doc: more about the GQview patch
!! doc: how to tag images, videos etc.
!! feature: emulate read and write of *.meta files (not enough detail in error
   messages)
!! feature: add tags and description to a tag (not too hard, use special
   `fs', and map `ino' using extra table)
!! feature: read(2) based meta/adm interface -- readlink(2) is not good to
   execute a command, because mc(1) would read the links when `cd meta/adm'
!! feature: add values to tags, e.g. `user.foo="bar"' for tag `foo'.
!! rethink: prepending :%x:%s: to short names ruins their sort order
!! feature: multiple filesystem support based on UUID (this would survive
   migration quite easily)
!! feature: retain tags and description when file is copied (RELEASE op.)
!! feature: link files together: if tags or description change in one file,
   automatically change on the other, too. Possibly do this automatically on
   a copy. Or should we add a ``parent inode pointer''? That would make it
   problematic query in multiple levels.
!! doc: how to migrate
!! doc: example session with shell command lines earlier
!! doc: qiv-command `mv' support
!! feature: import tags from ~/.gqview/metadata/home/you/foo.jpg.meta
!! feature: patch GQview to use us (setxattr) instead of ~/.gqview/metadata
   Dat: gqview is good, always use UTF-8 in .meta files
   Change at `Store keywords and comments local to source images'.
!! feature: tag-add-timestamp for easy undo
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
!! Dat: MySQL fulltext <50% threshold even without `IN NATURAL LANGUAGE MODE'
!! try: search without a stat (chdir(), stat(), ls(1))
!! try: chdir(), readdir()
!! think: fulltext index needs MyISAM tables. Do they survive a system
   crash? No, because MyISAM is not journaling. So we should have a copy of
   the words in a regular InnoDB table, too.
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
!! fix: avoid target file already exists when moving to `meta/tag/$TAGNAME'
   in Midnight Commander; What if symlink by that name already exists?
	   Better to keep `meta/tag' empty.
!! doc: file manager with POSIX extended attributes (not Midnight Commander)
!! SUXX: qiv, when moving to .qiv_trans, tries to remove principal name :-(
   unlink() fails, 2 links to file remain
!! test with MySQL 4.1
!! speed: why is `setfattr --restore' so slow?
!! feature: fulltext search on descriptions
!! feature: edit extended attributes in Midnight Commander
!! test suite
!! SUXX: getfattr(1) calls FUSE LISTXATTR twice -- why? Be smart, Perl...
!! feature: remove stale files
!! feature: keep metadata after file has been removed
!! feature: SYMLINK(../../root/proba/b,/root/proba/c/b)
   <- mv /tmp/mp/tagged/food/b /tmp/mp/root/proba/c
!! feature: rename fs in fss
!! measure: do we need the %dev_to_fss cache?
!! feature: add two tags: move to "meta/tag/dance upskirt"
!! feature: recursive carrier watch with inotify or fschange
!! feature: find by principal without stat() -- is that faster?
!! SUXX: Midnight Commander cannot create multiple symlinks at once
!! feature: Midnight Commander menu integration
!! doc: strange: search for 'foo bar' -- it is 'foo' or `bar'
!! fix: move bride to wedding (rename tag)
!! fix: move from tagged/a/ to tagged/b/
!! doc: rfsdelta
!! doc: metainformation -> metadata
!! test: are prepred statements processen on the client side or in the
   MySQL server?
!! feature: remove stale `meta/search/*' symlinks with `meta/adm/fixunlink'

__END__
