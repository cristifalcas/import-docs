#!/usr/bin/perl -w
my @crt_timeData = localtime(time);
foreach (@crt_timeData) {$_ = "0$_" if($_<10);}
print "Start: ". ($crt_timeData[5]+1900) ."-".($crt_timeData[4]+1)."-$crt_timeData[3] $crt_timeData[2]:$crt_timeData[1]:$crt_timeData[0].\n";
use warnings;
use strict;
$| = 1;

# perl -e 'print sprintf("\\x{%x}", $_) foreach (unpack("C*", "Ó"));print"\n"' 

$SIG{__WARN__} = sub { die @_ };
# categories:
# $file_url -> $rest_dir[length], $ver, $cust
# $rest_dir[length] -> $rest_dir[length-1]
# $rest_dir[length-1] -> $rest_dir[length-2]
# ......
# $rest_dir[1] -> $rest_dir[0]
# $rest_dir[0] -> $ver
# $ver -> $main, $big_ver
# $main -> $big_ver, $dir_type, $wiki_first_category
# $big_ver -> $customer, $dir_type, $wiki_first_category
# $customer -> $dir_type, $wiki_first_category
# $dir_type -> $wiki_first_category

### for each page check in $to_keep for the same md5 with real link;
#     if does not exist, create a new page, else a link to it
#    after importing a new page, add it to $to_keep


# active main,ver naming: the ones returned from mefs query
# active customers: from marinels query
# svn checkout: only the above versions or from the above customers. For a customers all.
# naming:
#   separator between fields will be " -- " (replace slash with sep)
#   underscore to space
#   every word starts with upper case
#   version naming:
#     doc file name_main _ver_appended_dir names up to Documents
#    customer naming:
#      doc file name_customer_main _ver_appended_dir names up to Documents
# info to keep for each file in WIKI_BASE_WORK_DIR WIKI_PAGE_TITLE:
#   work dir. Contains:
#     pics, wiki text, zipped doc
#   file with name uploaded_files. Contains:
#     files added to wiki: File:pics, File:ziped doc, wiki url
#   file with name info. Contains:
#     doc:md5sum of doc file
#     relative path after SVN_LOCAL_BASE_PATH (to see if the file was removed or not)
#     link or real
# if md5 of doc can be found someplace else, make the doc a link to the first one found
#  pages update (delete, add, new):
#    for versions: if we can't find the saved file in the svn dir, remove it
#    for customers: if we can't find the saved file in customers svn dir, remove it


# eval 'exec /usr/bin/perl  -S $0 ${1+"$@"}'
#     if 0; # not running under some shell

# die "We need the dir where the doc files are and the type of the dir: mind_svn, users, sc_docs.\n" if ( $#ARGV <= 1 );

use Cwd 'abs_path';
use File::Basename;
use File::Copy;
use File::Find;
use Getopt::Std;

my $path_prefix = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
print "$path_prefix\n";
# my $real_path = abs_path($0);
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."our_perl_lib/lib";

use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
# use Digest::MD5 qw(md5 md5_hex md5_base64);
use Text::Balanced;
# use Encode;
use URI::Escape;
use File::Path qw(make_path remove_tree);
use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init({ level   => $DEBUG,
#                            file    => ">>test.log" 
# 			   layout   => "%d [%5p] (%6P) [%rms] [%M] - %m{chomp}\t%x\n",
			   layout   => "%5p (%6P) %m{chomp}\n",
});

use Mind_work::WikiWork;
use Mind_work::WikiCommons;
use Mind_work::WikiClean;
use Mind_work::WikiMindUsers;
use Mind_work::WikiMindSVN;
use Mind_work::WikiMindSC;
use Mind_work::WikiMindCRM;
use Mind_work::WikiMindCMS;

use File::Slurp;
use DBI;
my ($wikidb_server, $wikidb_name, $wikidb_user, $wikidb_pass) = ();
open(FH, "/var/www/html/wiki/LocalSettings.php") or LOGDIE "Can't open file for read: $!.\n";
while (<FH>) {
  $wikidb_server = $2 if $_ =~ m/^(\s*\$wgDBserver\s*=\s*\")(.+)(\"\s*;\s*)$/;
  $wikidb_name = $2 if $_ =~ m/^(\s*\$wgDBname\s*=\s*\")(.+)(\"\s*;\s*)$/;
  $wikidb_user = $2 if $_ =~ m/^(\s*\$wgDBuser\s*=\s*\")(.+)(\"\s*;\s*)$/;
  $wikidb_pass = $2 if $_ =~ m/^(\s*\$wgDBpassword\s*=\s*\")(.+)(\"\s*;\s*)$/;
}
close(FH);
my $dbh_mysql = DBI->connect("DBI:mysql:database=$wikidb_name;host=$wikidb_server", "$wikidb_user", "$wikidb_pass");
# my $sth_mysql = $dbh_mysql->do("CREATE TABLE IF NOT EXISTS mind_wiki_info (WIKI_NAME VARCHAR( 255 ) NOT NULL ,FILES_INFO_INSERTED VARCHAR( 9000 ) ,PRIMARY KEY ( WIKI_NAME ) )");

# declare the perl command line flags/options we want to allow
my $options = {};
getopts("rd:n:c:", $options);

our $remote_work = "no";
if ($options->{'r'}){
    $remote_work = "yes";
}

my $all_real = "no";
my $delete_everything = "no";
my $delete_categories = "yes";
my $make_categories = "yes";
my $big_dump_mode = "no";
my $delete_previous_page = "yes";
my $pid_old = "100000";
my $max_to_delete = 1000;
my $type_old = "";
my $lo_user;
my $docs_nr_forks = 2;
my $links_nr_forks = 5;
my $crm_nr_forks = 5;
my $sc_nr_forks = 3;

if (defined $options->{'c'}) {
    if ($options->{'c'} =~ m/^y$/i){
# 	$delete_categories = "yes";
	$make_categories = "yes";
    }
    if ($options->{'c'} =~ m/^n$/i){
# 	$delete_categories = "no";
	$make_categories = "no";
    }
}

my $our_wiki;
my $path_files = abs_path($options->{'d'});
my $path_type = $options->{'n'};
my @tmp = fileparse($path_files, qr/\.[^.]*/);
our $wiki_dir = "$path_prefix/work/workfor_". $tmp[0].$tmp[2] ."";
WikiCommons::makedir $wiki_dir;
$wiki_dir = abs_path($wiki_dir);

my $bad_dir = "$path_prefix/work/bad_dir";
WikiCommons::makedir $bad_dir;
my $pid_file = "$path_prefix/work/mind_importing_$path_type.pid";
my $remote_work_path = "$path_prefix/remote_batch_files";

my $wiki_result = "result";
my $wiki_files_uploaded = "wiki_files_uploaded.txt";
my ($failed, $to_delete, $to_keep, $pages_toimp_hash, $pages_local_hash, $redirect_toimp_hash);

my $md5_pos = 0;
my $rel_path_pos = 1;
my $svn_url_pos = 2;
my $link_type_pos = 3;
my $categories_pos = 4;

my $count_files;
our $coco;
WikiCommons::is_remote("$remote_work");
WikiCommons::set_real_path($path_prefix);
chdir "/tmp/" || die "can't go to /tmp.\n";

sub add_swf_users {
    my ($doc_file, $work_dir, $new_file, $suffix, $zip_name) = @_;
    WikiCommons::generate_html_file( $doc_file, "swf", $lo_user );
    WikiCommons::generate_html_file( $doc_file, "pdf", $lo_user );
    LOGDIE "no pdf created in $work_dir/$new_file.pdf" if ! -s "$work_dir/$new_file.pdf";
    `pdftotext "$work_dir/$new_file.pdf"`;
    LOGDIE "no good" if ($?) || ! -s "$work_dir/$new_file.txt" || ! -s "$work_dir/$new_file.pdf" || ! -s "$work_dir/$new_file.swf";
    unlink "$work_dir/$new_file.pdf"; 
    copy("$work_dir/$new_file.swf","/var/www/html/ppt_as_flash/users_imports/") or LOGDIE "Copy swf failed.\n";

    open (FILEHANDLE, "$work_dir/$new_file.txt") or LOGDIE "can't read txt file: ".$!."\n";
    my $wiki = do { local $/; <FILEHANDLE> };
    close (FILEHANDLE);
    $wiki =~ s/\n/\n\n/gm;
    $wiki = "<swf width=\"800\" height=\"500\" >http://10.0.0.99/ppt_as_flash/users_imports/$new_file.swf</swf> \n\n<!-- <nowiki>\n$wiki\n</nowiki> -->";

    my $zip = Archive::Zip->new();
    $zip->addFile( "$work_dir/$new_file$suffix", "$new_file$suffix") or LOGDIE "Error adding file $new_file$suffix to zip.\n";
    $zip->writeToFileNamed( "$work_dir/$wiki_result/$zip_name.zip" ) == AZ_OK or LOGDIE "Write error for zip file.\n";
#     open (FILE, ">>$work_dir/$wiki_files_uploaded") or LOGDIE "at create wiki can't open file $work_dir/$wiki_files_uploaded for writing: $!\t". (WikiCommons::get_time_diff) ."\n";
#     print FILE "File:$new_file.swf\n";
#     print FILE "File:$zip_name.zip\n";
#     close (FILE);

    return $wiki;
}

sub create_wiki {
    my ($page_url, $doc_file, $zip_name) = @_;
    LOGDIE "Page url is empty.\n" if $page_url eq '';
    $zip_name = $page_url if ! defined $zip_name;
    my $work_dir = "$wiki_dir/$page_url";

    my ($name_url, $dir_url, $suffix_url) = fileparse($page_url, qr/\.[^.]*/);
    my ($name, $dir, $suffix) = fileparse($doc_file, qr/\.[^.]*/);
    if ( -d $work_dir) {
	INFO "Path $work_dir already exists. Moving to $bad_dir.\t". (WikiCommons::get_time_diff) ."\n" ;
	my $name_bad = "$bad_dir/$page_url".time();
	WikiCommons::makedir("$name_bad");
	WikiCommons::move_dir("$work_dir", "$name_bad");
	LOGDIE "Directory still exists." if ( -d $work_dir);
    }
    WikiCommons::makedir ("$work_dir");
    $name = WikiCommons::normalize_text($name);

    my $new_file = "$name_url$suffix_url";
    copy("$doc_file","$work_dir/$new_file$suffix") or LOGDIE "Copy failed for $page_url at create_wiki: $doc_file to $work_dir: $!\t". (WikiCommons::get_time_diff) ."\n";
    $doc_file = "$work_dir/$new_file$suffix";
    my $dest = "$work_dir/$wiki_result";
    WikiCommons::makedir ($dest);

    if ( -f $doc_file ) {
	if ($suffix =~ m/^\.pptx?$/i) {
	    return add_swf_users($doc_file, $work_dir, $new_file, $suffix, $zip_name);
	}
	WikiCommons::generate_html_file( $doc_file, "html", $lo_user );
	my $html_file = "$work_dir/$new_file.html";

	if ( -f $html_file && ! -e ".~lock.$new_file#") {
	    my ($wiki, $image_files) = WikiClean::make_wiki_from_html ( $html_file );
	    return undef if (! defined $wiki );

	    WikiCommons::add_to_remove ("$work_dir/$wiki_result", "dir");

	    my %seen = ();
	    open (FILE, ">>$work_dir/$wiki_files_uploaded") or LOGDIE "at create wiki can't open file $work_dir/$wiki_files_uploaded for writing: $!\t". (WikiCommons::get_time_diff) ."\n";
	    INFO "\t-Moving pictures and making zip file.\t". (WikiCommons::get_time_diff) ."\n";
	    foreach my $img (@$image_files){
		move ($img, $dest) or LOGDIE "Moving file \"$img\" failed: $!\t". (WikiCommons::get_time_diff) ."\n" unless $seen{$img}++;
		my ($img_name,$img_dir,$img_suffix) = fileparse($img, qr/\.[^.]*/);
		print FILE "File:$img_name$img_suffix\n";
	    }
	    $image_files = ();

	    my $zip = Archive::Zip->new();
	    $zip->addFile( "$work_dir/$new_file$suffix", "$new_file$suffix") or LOGDIE "Error adding file $new_file$suffix to zip.\t". (WikiCommons::get_time_diff) ."\n";
	    LOGDIE "Write error for zip file.\t". (WikiCommons::get_time_diff) ."\n" if $zip->writeToFileNamed( "$dest/$zip_name.zip" ) != AZ_OK;
	    print FILE "File:$zip_name.zip\n";
	    close (FILE);
	    INFO "\t+Moving pictures and making zip file.\t". (WikiCommons::get_time_diff) ."\n";

	    WikiCommons::add_to_remove( $doc_file, "file" );
	    WikiCommons::add_to_remove( $html_file, "file" );
	    return $wiki;
	} else {
	    INFO "OpenOffice could not create the html file.\t". (WikiCommons::get_time_diff) ."\n";
	    return;
	}
    } else {
	 INFO "Strange, can't find the doc file in $work_dir.\t". (WikiCommons::get_time_diff) ."\n";
	 return;
    }
}

sub get_existing_pages {
    opendir(DIR, "$wiki_dir") || die("Cannot open directory $wiki_dir.\n");
    my @allfiles = grep { (!/^\.\.?$/) && -d "$wiki_dir/$_" } readdir(DIR);
    closedir(DIR);
    $_ = "$wiki_dir/".$_ foreach (@allfiles);

    $count_files = 0;
    INFO "-Searching for files in db.\t". (WikiCommons::get_time_diff) ."\n";
    my $total = scalar @allfiles;
    my $crt_nr = 0;
    foreach my $dir (sort @allfiles) {
	if (-d "$dir") {
	    next if ($dir eq "$wiki_dir/categories");
	    $crt_nr++;
	    INFO "\tDone $crt_nr from a total of $total.\t". (WikiCommons::get_time_diff) ."\n" if ($crt_nr%2000 == 0);
	    my ($name,$dir_dir,$suffix) = fileparse($dir, qr/\.[^.]*/);
	    $name = "$name$suffix";
# if ( -f "$dir/$wiki_files_info" && -s "$dir/$wiki_files_info") {
# my $info_text = read_file( "$dir/$wiki_files_info" ) ;
# my $sth_mysql = $dbh_mysql->do("REPLACE INTO mind_wiki_info (WIKI_NAME,FILES_INFO_INSERTED) VALUES (".$dbh_mysql->quote($name).", ".$dbh_mysql->quote($info_text).")");
# }
	    my $ret = $dbh_mysql->selectrow_arrayref("select FILES_INFO_INSERTED from mind_wiki_info where WIKI_NAME=".$dbh_mysql->quote($name)); 
	    if (defined $ret) {
		my @info_text = split "\n", @$ret[0];
		chomp(@info_text);
		if ( @info_text != 4 ) {
		    INFO "\tFile $name does not have the correct number of entries.\n".Dumper(@info_text);
		    next;
		}

		my $md5 = $info_text[$md5_pos]; $md5 =~ s/(.*?)=\s*//;
		my $rel_path = $info_text[$rel_path_pos]; $rel_path =~ s/(.*?)=\s*//;
		my $svn_url = $info_text[$svn_url_pos]; $svn_url =~ s/(.*?)=\s*//;
		my $url_type = $info_text[$link_type_pos]; $url_type =~ s/(.*?)=\s*//;
		if (!(defined $md5 && defined $rel_path && defined $url_type && defined $svn_url)){
		    INFO "\tFile $name does not have the correct information.\n";
		    next;
		}
		$md5 =~ s/(^\s+|\s+$)//g;
		$rel_path =~ s/(^\s+|\s+$)//g;
		$svn_url =~ s/(^\s+|\s+$)//g;
		$url_type =~ s/(^\s+|\s+$)//g;
		LOGDIE "\tWe already have this url. But this is insane...\t". (WikiCommons::get_time_diff) ."\n" if (exists $pages_toimp_hash->{$dir});
		$pages_local_hash->{$name} = [$md5, $rel_path, $svn_url, $url_type, []];
		++$count_files;
	    } else {
		INFO "\tThis is not a correct wiki info: $name\n";
		my @q = split '/', $dir;
		my $name_bad = "$bad_dir/$q[$#q]".time();
# 		WikiCommons::makedir("$name_bad");
		WikiCommons::move_dir("$dir","$name_bad");
		LOGDIE "\tDirectory still exists." if ( -d $dir);
	    }
	} else {
	    INFO "\tExtra files in wiki dir: $dir\n";
	}
    }
    INFO "\tTotal number of files: ".($count_files)."\t". (WikiCommons::get_time_diff) ."\n";
    INFO "+Searching for files in db.\t". (WikiCommons::get_time_diff) ."\n";
}

sub generate_new_updated_pages {
    ### sort already existing files and svn files
    ## if it's the same url and (md5, rel_path) we should keep it, so we remove it from svn hash
    ##    else we need to delete and reimpot it
    foreach my $url (sort keys %$pages_local_hash) {
	## local and svn are the same thing
	if (exists $pages_toimp_hash->{$url} &&
		$pages_local_hash->{$url}[$md5_pos] eq $pages_toimp_hash->{$url}[$md5_pos] &&
		$pages_local_hash->{$url}[$rel_path_pos] eq $pages_toimp_hash->{$url}[$rel_path_pos] ) {
	    $to_keep->{$url} = $pages_toimp_hash->{$url};
	    $to_keep->{$url}[$link_type_pos] = $pages_local_hash->{$url}[$link_type_pos];
	    delete($pages_toimp_hash->{$url});
	} else {
	    if (exists $pages_toimp_hash->{$url}) {
		INFO "Url $url will be updated because: \n\t\tcrt_md5\n\t\t\t$pages_local_hash->{$url}[$md5_pos] <> \n\t\t\t$pages_toimp_hash->{$url}[$md5_pos] or \n\t\tcrt_rel_path \n\t\t\t$pages_local_hash->{$url}[$rel_path_pos] <> \n\t\t\t$pages_toimp_hash->{$url}[$rel_path_pos].\n";
	    } else {
		INFO "Delete url $url because it doesn't exist anymore.\n";
		$to_delete->{$url} = $pages_local_hash->{$url};
	    }
	}
    }
}

sub generate_real_and_links {
    ### clean up already existing files
    ## for each md5 that is the same from to_keep, we must have 1 and only one real url, all others - links
    ## so, if we have 0 real urls, we remove all pages
    ##        if we have > 1 real urls, we delete all but one
    ##make a map (HoHoA) with keys md5,link_type and values url

    my $md5_map = {};
    push @{$md5_map->{$to_keep->{$_}[$md5_pos]}{$to_keep->{$_}[$link_type_pos]}}, ($_) foreach (sort keys %$to_keep);
    # when making pages, check md5 in to_keep. If it exists, make a link, otherwise make a page and add it to to_keep
    foreach my $md5 (sort keys %$md5_map) {
	my $nr_real = 0;
	my $nr_link = 0;
	$nr_real = scalar @{ $md5_map->{$md5}{"real"} } if (exists $md5_map->{$md5}{"real"});
	$nr_link = scalar @{ $md5_map->{$md5}{"link"} } if (exists $md5_map->{$md5}{"link"});
	if ( $nr_real == 0 ) {
	    my $q = $md5_map->{$md5}{"link"};
	    foreach my $url (@$q) {
		INFO "Remove link url $url because of all links: $nr_link.\n";
		$to_delete->{$url} = $to_keep->{$url} if (exists $to_keep->{$url});
		$pages_toimp_hash->{$url} = $to_keep->{$url} if (exists $to_keep->{$url});
		delete($to_keep->{$url});
	    }
	}
	if ( $nr_real > 1 ) {
	    my $q = $md5_map->{$md5}{"real"};
	    for (my $i=0; $i < $nr_real - 1; $i++) {
		INFO "Remove real url @$q[$i] because of too many real links: $nr_real.\n";
		$to_delete->{@$q[$i]} = $to_keep->{@$q[$i]};
		$pages_toimp_hash->{@$q[$i]} = $to_keep->{@$q[$i]};
		delete($to_keep->{@$q[$i]});
		$pages_toimp_hash->{@$q[$i]}[$link_type_pos] = "link";
	    }
	    $q = $md5_map->{$md5}{"link"};
	    foreach my $url (@$q) {
		INFO "Remove link url $url because of too many real links: $nr_real.\n";
		$to_delete->{$url} = $to_keep->{$url} if (exists $to_keep->{$url});
		$pages_toimp_hash->{$url} = $to_keep->{$url} if (exists $to_keep->{$url});
		$pages_toimp_hash->{$url}[$link_type_pos] = "link";
		delete($to_keep->{$url});
	    }
	}
    }
}

sub generate_cleaned_real_and_links {
    ## for all pages that need to be imported, make one real and let all the rest links
    my $md5_map = {};
    my $md5_map_keep = {};
    return if ($all_real eq "yes");
    INFO "\tstart checking for links.\n";
    push @{$md5_map->{$pages_toimp_hash->{$_}[$md5_pos]}{$pages_toimp_hash->{$_}[$link_type_pos]}}, ($_) foreach (sort keys %$pages_toimp_hash);
    push @{$md5_map_keep->{$to_keep->{$_}[$md5_pos]}{$to_keep->{$_}[$link_type_pos]}}, ($_) foreach (sort keys %$to_keep);

    my %tmp = %$pages_toimp_hash;
    ## all from $md5_map are links, so we only make 1 real if we don't have anything in $md5_map_keep
    my $count=0;my $total = scalar keys %$md5_map;
    foreach my $key (keys %$md5_map) {
	if (! exists $md5_map_keep->{$key}){
	    foreach my $url (sort keys %tmp){
		if ($pages_toimp_hash->{$url}[$md5_pos] eq $key) {
		    delete $tmp{$url};
		    $pages_toimp_hash->{$url}[$link_type_pos] = "real";
		    last;
		}
	    }
	}
	INFO "done $count out of $total.\t". (WikiCommons::get_time_diff) ."\n" if ++$count%1000 == 0;
    }
}

sub generate_pages_for_real_and_redir {
    if ( $big_dump_mode ne "yes" && ($path_type eq "sc_docs" || $path_type =~ m/^crm_/i )){
	my $redirect_url = "";
	### we import SC_XXX, but not SC:
	### SC: exists only in to_keep,
	foreach my $url (keys %$pages_toimp_hash) {
	    if ( $url =~ m/^SC_(.*)?:(.*)$/i || $url =~ m/^CRM_(.*)?:(.*)$/i ) {
		my $ns = $1; my $url_name = $2;
		$redirect_url = "SC:$url_name" if $url =~ m/^SC_/;
		$redirect_url = "CRM:$url_name" if $url =~ m/^CRM_/;
		if (defined $to_keep->{$redirect_url} && ! defined $pages_toimp_hash->{$redirect_url}) {
		    $to_delete->{$redirect_url} = $to_keep->{$redirect_url};
		    $pages_toimp_hash->{$redirect_url} = $to_keep->{$redirect_url};
		    delete ($to_keep->{$redirect_url});
		}
	    }
	}
	### we import SC:, but we don't import SC_XXX:
	### SC_XXX exists only in to_keep
	foreach my $url (keys %$to_keep) {
	    if ( $url =~ m/^SC_(.*)?:(.*)$/i || $url =~ m/^CRM_(.*)?:(.*)$/i ) {
		my $ns = $1; my $url_name = $2;
		$redirect_url = "SC:$url_name" if $url =~ m/^SC_/;
		$redirect_url = "CRM:$url_name" if $url =~ m/^CRM_/;
		if (defined $pages_toimp_hash->{$redirect_url} && ! defined $pages_toimp_hash->{$url}) {
		    $to_delete->{$url} = $to_keep->{$url};
		    $pages_toimp_hash->{$url} = $to_keep->{$url};
		    delete ($to_keep->{$url});
		}
	    }
	}
    }
}

sub generate_pages_to_delete_to_import {
    INFO "Start generating new/updated/to_delete/to_keep urls.\t". (WikiCommons::get_time_diff) ."\n";
    generate_new_updated_pages();
    INFO "Done generating new/updated urls.\t". (WikiCommons::get_time_diff) ."\n";
    generate_real_and_links();
    INFO "Done separating urls in real and links.\t". (WikiCommons::get_time_diff) ."\n";
    generate_pages_for_real_and_redir();
    INFO "Done cleaning real and redirects.\t". (WikiCommons::get_time_diff) ."\n";
    generate_cleaned_real_and_links();
    INFO "Done final cleaning of urls.\t". (WikiCommons::get_time_diff) ."\n";

    my $tmp = {};
    foreach (keys %$pages_toimp_hash) {$tmp->{$_} = 1 if ($pages_toimp_hash->{$_}[$link_type_pos] eq "link")};

    INFO "1. Number of files to import: ",scalar keys %$pages_toimp_hash,"\n";
    INFO "2. Number of files to import as links: ",scalar keys %$tmp,"\n";
    INFO "3. Number of files already imported: ",scalar keys %$to_keep,"\n";
    INFO "4. Number of files to delete: ",scalar keys %$to_delete,"\n";
}

sub make_categories {
    return 1 if ( $make_categories eq "no");
    my $url = "";

    my $general_categories_hash = $coco->get_categories;
    return if ($delete_everything eq "yes");
    my $categories_ref = $dbh_mysql->selectall_hashref("select WIKI_NAME from mind_wiki_info where WIKI_NAME like 'Category:%'", 'WIKI_NAME');
    INFO "-Making categories.\t". (WikiCommons::get_time_diff) ."\n";
    foreach my $key (sort keys %$general_categories_hash) {
	my $text = "----\n\n";
	$url = "Category:$key";
	next if defined $categories_ref->{$url};
	if (ref $general_categories_hash->{$key}) {
	    foreach my $sec_key (sort keys %{$general_categories_hash->{$key}} ) {
		$text .= "\[\[Category:$sec_key\]\]\n" if exists $general_categories_hash->{$key}->{$sec_key} ;
	    }
	}
	$text .= "----\n\n";
	if (WikiCommons::is_remote ne "yes"){
	    $our_wiki->wiki_edit_page($url, $text);
	    LOGDIE "Could not import url $url.\t". (WikiCommons::get_time_diff) ."\n" if ( ! $our_wiki->wiki_exists_page($url) );
	} else {
	    INFO "\tCopy category to $remote_work_path\n";
	    WikiCommons::makedir("$remote_work_path");
	    WikiCommons::write_file("$remote_work_path/$url.wiki", $text);
	}
	my $txt = "md5 = 0\nrel_path = 0\nsvn_url = 0\nlink_type = category\n";
# 	INFO "\t## adding to db new val $txt\n";
	my $sth_mysql = $dbh_mysql->do("REPLACE INTO mind_wiki_info 
		  (WIKI_NAME,FILES_INFO_INSERTED) VALUES 
		  (".$dbh_mysql->quote($url).", ".$dbh_mysql->quote($txt).")");
    }
    INFO "+Making categories.\t". (WikiCommons::get_time_diff) ."\n";
}

sub insertdata {
    my ($url, $wiki) = @_;
    my $work_dir = "$wiki_dir/$url";
    WikiCommons::write_file("$work_dir/$url.full.wiki", $wiki, 1);

    if (WikiCommons::is_remote ne "yes"){
	$our_wiki->wiki_import_files ("$work_dir/$wiki_result", "$url");
	INFO "\tDeleting url $url just to be sure.\t". (WikiCommons::get_time_diff) ."\n";
	$our_wiki->wiki_delete_page ($url) if ( $our_wiki->wiki_exists_page($url) && $delete_previous_page ne "no");
	INFO "\tImporting url $url.\t". (WikiCommons::get_time_diff) ."\n";
	$our_wiki->wiki_edit_page($url, $wiki);
	LOGDIE "Could not import url $url.\t". (WikiCommons::get_time_diff) ."\n" if ( ! $our_wiki->wiki_exists_page($url) );
	INFO "\tDone $url.\t". (WikiCommons::get_time_diff) ."\n";
    } else {
	INFO "\tCopy files to $remote_work_path/$wiki_result\n";
	WikiCommons::makedir("$remote_work_path/$wiki_result");
	WikiCommons::add_to_remove ("$remote_work_path/$wiki_result", "dir");
	WikiCommons::copy_dir ("$work_dir/$wiki_result", "$remote_work_path/$wiki_result") if -e "$work_dir/$wiki_result";
	copy("$work_dir/$url.full.wiki","$remote_work_path/$url") or LOGDIE "Copy failed for: $url.full.wiki to $remote_work_path: $!\t". (WikiCommons::get_time_diff) ."\n";
    }

    my $text = "md5 = ".$pages_toimp_hash->{$url}[$md5_pos]."\n";
    $text .= "rel_path = ".$pages_toimp_hash->{$url}[$rel_path_pos]."\n";
    $text .= "svn_url = ".$pages_toimp_hash->{$url}[$svn_url_pos]."\n";
    $text .= "link_type = ".$pages_toimp_hash->{$url}[$link_type_pos]."\n";
#     INFO "\t## adding to db new val $text\n";
    my $sth_mysql = $dbh_mysql->do("REPLACE INTO mind_wiki_info (WIKI_NAME,FILES_INFO_INSERTED) VALUES (".$dbh_mysql->quote($url).", ".$dbh_mysql->quote($text).")");
    delete($pages_toimp_hash->{$url});

    my $fail = 0;
    $fail = WikiCommons::cleanup($work_dir);
    opendir(DIR, $work_dir);
    my @files = grep { (!/^\.\.?$/) } readdir(DIR);
    closedir(DIR);
    if ($fail){
	my $name_bad = "$bad_dir/$url".time();
	WikiCommons::makedir("$name_bad");
	WikiCommons::move_dir("$work_dir","$name_bad");
    }
#     delete $failed->{$url};
}

sub work_begin {
    WikiCommons::reset_time();
    get_existing_pages;

    if ($delete_everything eq "yes") {
	$to_delete->{$_} = $pages_local_hash->{$_} foreach (sort keys %$pages_local_hash);
	$pages_toimp_hash = {};
    } else {
	$pages_toimp_hash = $coco->get_documents();

	if ($path_type eq "users") {
	    my $disabled = $coco->get_disabled_pages();
	    foreach my $key (keys %$disabled){
		delete( $pages_local_hash->{$key});
	    }
	}
	generate_pages_to_delete_to_import();
    }
    if (WikiCommons::is_remote ne "yes") {
        LOGDIE Dumper(sort keys %$to_delete)."\nToo many to delete.\n" if (keys %$to_delete) > $max_to_delete;
	foreach my $url (sort keys %$to_delete) {
	    INFO "Deleting $url.\t". (WikiCommons::get_time_diff) ."\n";
	    remove_tree("$wiki_dir/$url") || LOGDIE "Can't remove dir $wiki_dir/$url: $?.\n";
	    my $sth_mysql = $dbh_mysql->do("DELETE FROM mind_wiki_info where WIKI_NAME=".$dbh_mysql->quote($url));
	    $our_wiki->wiki_delete_page($url) if ( $our_wiki->wiki_exists_page($url) );
	    $url =~ s/^(SC[^:]*)/SC_Deployment/;
	    $our_wiki->wiki_delete_page($url) if ( $our_wiki->wiki_exists_page($url) );
	}
    }
    use Storable qw(dclone);
    $failed = dclone($pages_toimp_hash);
}

sub work_for_docs {
    make_categories if scalar keys %$pages_toimp_hash;
    fork_function($docs_nr_forks, \&real_worker) if scalar keys %$pages_toimp_hash;
    ## make links to real pages
    my $md5_map = {};
    push @{$md5_map->{$to_keep->{$_}[$md5_pos]}{$to_keep->{$_}[$link_type_pos]}}, ($_) foreach (keys %$to_keep);
    foreach my $md5 (keys %$md5_map) {
	my $nr_real = 0; $nr_real = scalar @{ $md5_map->{$md5}{"real"} } if (exists $md5_map->{$md5}{"real"});
	my $nr_link = 0; $nr_link = scalar @{ $md5_map->{$md5}{"link"} } if (exists $md5_map->{$md5}{"link"});
	LOGDIE "We should only have ONE real link: real=$nr_real link=$nr_link, md5=$md5.\n".Dumper($md5_map->{$md5}) if ($nr_real != 1);
    }
    fork_function($links_nr_forks, \&link_worker, $md5_map) if scalar keys %$pages_toimp_hash;
}

sub split_redirects {
    INFO "\tExtracting redirects.\n";
    foreach my $url (sort keys %$pages_toimp_hash) {
	if ($url !~ m/^(SC|CRM):(.*)$/i) {
	    my ($type_full, $type, $crt_name) = ($url =~ m/((SC|CRM)[ _].+)?:(.*)/i);
	    $redirect_toimp_hash->{"$type:$crt_name"}->{'url'} = $url;
	    $redirect_toimp_hash->{"$type:$crt_name"}->{'info'} = $pages_toimp_hash->{"$type_full:$crt_name"};
	    delete($pages_toimp_hash->{"$type_full:$crt_name"});
	}
    }
}

sub make_redirect {
    my ($crt_name, $wrong_hash) = @_;   ## short url
    my $url = $redirect_toimp_hash->{$crt_name}->{'url'}; ## full url

    WikiCommons::makedir "$wiki_dir/$url/";
    if ($crt_name =~ m/^SC:/i && (! $our_wiki->wiki_exists_page($crt_name) || defined $wrong_hash->{$url})) {
	remove_tree("$wiki_dir/$url/") if -d "$wiki_dir/$url/";
	remove_tree("$wiki_dir/$crt_name/") if -d "$wiki_dir/$crt_name/";
	next;
    }

    INFO "\tmake redirect from $crt_name to $url.\n";
    $our_wiki->wiki_delete_page("$url") if $our_wiki->wiki_exists_page("$url") && $delete_previous_page ne "no";
    $our_wiki->wiki_move_page("$crt_name", "$url");

    my $text = "md5 = ".$redirect_toimp_hash->{$crt_name}->{'info'}[$md5_pos]."\n";
    $text .= "rel_path = ".$redirect_toimp_hash->{$crt_name}->{'info'}[$rel_path_pos]."\n";
    $text .= "svn_url = ".$redirect_toimp_hash->{$crt_name}->{'info'}[$svn_url_pos]."\n";
    $text .= "link_type = ".$redirect_toimp_hash->{$crt_name}->{'info'}[$link_type_pos]."\n";
    my $redirect_text = "#redirect [[$url]]";
    WikiCommons::write_file("$wiki_dir/$url/$crt_name.wiki", "$redirect_text");
    WikiCommons::write_file("$wiki_dir/$url/$wiki_files_uploaded", "");
    my $sth_mysql = $dbh_mysql->do("REPLACE INTO mind_wiki_info (WIKI_NAME,FILES_INFO_INSERTED) VALUES (".$dbh_mysql->quote($url).", ".$dbh_mysql->quote($text).")");
    delete $redirect_toimp_hash->{$crt_name};
#     delete $failed->{$url};
}

sub fork_function {
    my ($nr_threads, $function, @function_args) = @_;
    use POSIX ":sys_wait_h";
    INFO "Start forking.\n";
    my ($running, $links);
    my $total_nr = scalar keys %$pages_toimp_hash;
    my $crt_nr = 0;
    my @thread = (1..$nr_threads);

    while (1) {
# INFO Dumper(scalar @thread, scalar keys %$running, keys %$pages_toimp_hash);
	my $crt_thread = shift @thread if scalar keys %$pages_toimp_hash;
	if (defined $crt_thread) {
	    my $url = (sort keys %$pages_toimp_hash)[0];
	    INFO "Got new thread to run $url\n";
# if ($url !~ m/B109856$/){push @thread, $crt_thread;delete $pages_toimp_hash->{$url};next;}
	    my $val = $pages_toimp_hash->{$url};
	    $crt_nr++;
	    INFO "************************* $crt_nr of $total_nr\n";
	    INFO "Making url for $url.\t". (WikiCommons::get_time_diff) ."\n";
	    my $pid = fork();
	    if (! defined ($pid)){
		LOGDIE  "Can't fork.\n";
	    } elsif ($pid==0) {
		INFO "Start fork function $url.\n";
		WikiCommons::reset_time();
		my $child_dbh = $dbh_mysql->clone();
		$dbh_mysql->{InactiveDestroy} = 1;
		undef $dbh_mysql;
		$dbh_mysql = $child_dbh;
		$function->($url, $val, $crt_thread, @function_args);
		exit 100;
	    }
	    $running->{$pid}->{'thread'} = $crt_thread;
	    $running->{$pid}->{'url'} = $url;
	    $running->{$pid}->{'val'} = $val;
	    delete $pages_toimp_hash->{$url};
	}

	## clean done children
	my $pid = waitpid(-1, WNOHANG);
	my $exit_status = $? >> 8;
	if ($pid > 0) {
	    INFO "child $pid died, from id with status=$exit_status: reapead.\n";
	    my $url = $running->{$pid}->{'url'};
	    push @thread, $running->{$pid}->{'thread'};
	    $to_keep->{$url} = $running->{$pid}->{'val'} if $exit_status == 0;
	    delete $failed->{$url} if $exit_status == 0;
	    delete $failed->{$redirect_toimp_hash->{$url}->{'url'}} if $exit_status == 0 && defined $redirect_toimp_hash->{$url};
	    delete $redirect_toimp_hash->{$url} if $exit_status == 0;
	    $links->{$url} = $running->{$pid}->{'val'} if $exit_status == 10;
	    delete $running->{$pid};
	}
	## don't sleep if not all threads are running and we still have work to do
	sleep 1 if !(scalar @thread && scalar keys %$pages_toimp_hash);
	## if no threads are working and there is no more work to be done
	last if scalar @thread == $nr_threads && scalar keys %$pages_toimp_hash == 0;
    }
    $pages_toimp_hash->{$_} = $links->{$_} foreach keys %$links;
}

sub crm_worker {
    my ($url, $val, $thread) = @_;
    eval{
    WikiCommons::reset_time();
    WikiCommons::makedir "$wiki_dir/$url/";
    my $rel_path = $val->[$rel_path_pos];
    INFO "$path_files/$rel_path\n";
    local( $/, *FH ) ;
    open(FH, "$path_files/$rel_path") || die("Could not open file: $!");
    my $wiki_txt = <FH>;
    close (FH);

    WikiCommons::makedir "$wiki_dir/$url/$wiki_result";
    WikiCommons::add_to_remove("$wiki_dir/$url/$wiki_result", "dir");
    my $work_dir = "$wiki_dir/$url";
    WikiCommons::write_file("$work_dir/$url.wiki", $wiki_txt);
    insertdata ($url, $wiki_txt);
    make_redirect($url);
    INFO "done crm $url.\n";
    }; ## eval
    if ($@ && $@ !~ m/^Exiting eval via next at/) {
	ERROR "Error generating crm for $url: $@\n";
	exit 1;
    }
    exit 0;
}

sub link_worker {
    my ($url, $val, $thread, $md5_map) = @_;
    my $sth_mysql = $dbh_mysql->do("DELETE FROM mind_wiki_info where WIKI_NAME=".$dbh_mysql->quote($url));
    eval{
    WikiCommons::reset_time();
    my $link_to = $md5_map->{$val->[$md5_pos]}->{"real"}[0];
    exit 1 if ! defined $link_to; ## probably the real page failed to import, so we ignore the links also
    LOGDIE "We should have a url in to_keep.\n" if (scalar @$val != scalar @{$to_keep->{$link_to}});
    my ($link_name,$link_dir,$link_suffix) = fileparse($to_keep->{$link_to}[$rel_path_pos], qr/\.[^.]*/);
    my ($name,$dir,$suffix) = fileparse($val->[$rel_path_pos], qr/\.[^.]*/);

    my $new_file = "$url$suffix";
    my $link_file = "$wiki_dir/$link_to/$link_to.wiki";
    WikiCommons::makedir("$wiki_dir/$url/");
    WikiCommons::write_file("$wiki_dir/$url/$wiki_files_uploaded", "");
    copy("$link_file","$wiki_dir/$url/$url.wiki") or LOGDIE "Copy failed for link: $link_file to $wiki_dir/$url: $!\t". (WikiCommons::get_time_diff) ."\n";
    open (FILEHANDLE, "$wiki_dir/$url/$url.wiki") or LOGDIE $!."\t". (WikiCommons::get_time_diff) ."\n";
    my $wiki = do { local $/; <FILEHANDLE> };
    close (FILEHANDLE);

    my $svn_url = $val->[$svn_url_pos];
    $svn_url = uri_escape( $svn_url,"^A-Za-z\/:0-9\-\._~%" );

    my $head_text = "<center>\'\'\'This file was shamesly copied from the following url: [[$link_to]] because the doc files are identical.\'\'\'\n\n";
    $head_text .= "The original document can be found at [$svn_url this address]\n" if ($svn_url ne "");
    $head_text .= "</center>\n----\n\n\n\n\n\n".$wiki."\n----\n\n";
    $wiki = $head_text;
    my $cat = $val->[$categories_pos];
    foreach (@$cat) {
	$wiki = $wiki."[[Category:$_]]" if ($_ ne "");
    }
    insertdata($url, $wiki);
    }; ## eval
    if ($@ && $@ !~ m/^Exiting eval via next at/) {
	ERROR "Error generating link for $url: $@\n";
	$sth_mysql = $dbh_mysql->do("DELETE FROM mind_wiki_info where WIKI_NAME=".$dbh_mysql->quote($url));
	exit 1;
    }
    exit 0;
}

sub real_worker {
    my ($url, $val, $thread) = @_;
    my $sth_mysql = $dbh_mysql->do("DELETE FROM mind_wiki_info where WIKI_NAME=".$dbh_mysql->quote($url));
    $lo_user = $lo_user."_$thread";
    exit 10 if $val->[$link_type_pos] eq "link" || WikiCommons::shouldSkipFile($url, "$path_files/$val->[$rel_path_pos]");
#     my $exit = 0;
    my $exit = eval {
      my $svn_url = $val->[$svn_url_pos];
      $svn_url = uri_escape( $svn_url,"^A-Za-z\/:0-9\-\._~%" );
      my $wiki = create_wiki($url, "$path_files/$val->[$rel_path_pos]");
      if (! defined $wiki ){
	  WikiCommons::makedir("$bad_dir/$url");
	  WikiCommons::move_dir("$wiki_dir/$url","$bad_dir/$url");
	  return 1;
      }
      my $head_text = "<center>\'\'\'This file was automatically imported from the following document: [[Media:$url.zip|$url.zip]]\'\'\'\n";
      $head_text .= "\nThe original document can be found at [$svn_url this address]\n" if ($svn_url ne "");
      $head_text .= "</center>\n----\n\n\n\n\n\n".$wiki."\n----\n\n";
      $wiki = $head_text;
      my $cat = $val->[$categories_pos];
      foreach (@$cat) {
	  $wiki = $wiki."[[Category:$_]]" if ($_ ne "");
      }

      my ($name,$dir,$suffix) = fileparse($path_files."/".$val->[$rel_path_pos], qr/\.[^.]*/);
      insertdata($url, $wiki);
      if ($path_type eq "users"){
	  my $text_url = "[InternetShortcut]\nURL=". $our_wiki->wiki_geturl ."/index.php/$url";
	  WikiCommons::write_file ("$dir/$name.url", $text_url);
      }
      return 0;
    }; ## eval
    if ($@ && $@ !~ m/^Exiting eval via next at/) {
	ERROR "Error generating real for $url: $@\n";
	$sth_mysql = $dbh_mysql->do("DELETE FROM mind_wiki_info where WIKI_NAME=".$dbh_mysql->quote($url));
	exit 1;
    }
    exit $exit;
}

sub SC_general_info {
    my ($url, $ftp_links) = @_;
    my $rel_path = $pages_toimp_hash->{$url}[$rel_path_pos];
    my $has_deployment;
    foreach (@{ $pages_toimp_hash->{$url}[$categories_pos] }){
	$has_deployment = 'Y' if $_ =~ m/^has_deployment\s+Y$/i;
    }
    my $general_wiki_file = "General_info.wiki";
    local( $/, *FH ) ;
    open(FH, "$path_files/$rel_path/$general_wiki_file") || die("Could not open file: $!");
    my $wiki_txt = <FH>;
    close (FH);
    $wiki_txt =~ s/^[\f ]+|[\f ]+$//mg;
    $wiki_txt .= "\n\n'''FTP links:'''\n\n";
    foreach my $key (keys %$ftp_links) {
	$wiki_txt .= "[$ftp_links->{$key}/$rel_path $key]\n\n";
    }

    my ($affected) = $wiki_txt =~ m/^.*(\n\'\'\'Affected Features & Parameters.*?)\n+(\'\'\'Test remarks|\'\'\'FTP links)/gmsi;
    $affected = "" if ! defined $affected;
    my $deployment_txt = "This document has been flaged as having deployment consideration. Search for this also in [[$url#General Information|General Information]] and the other SC tabs imported.\n\n$affected\n" if defined $has_deployment && $has_deployment eq "Y";
    return ($wiki_txt, $deployment_txt);
}

sub sc_worker {
    my ($url, $val, $thread, $ftp_links, $info_h) = @_;
    $lo_user = $lo_user."_$thread";
    my $wrong_hash = {};
    eval {
# return if "$url" !~ "B621568";
    WikiCommons::makedir "$wiki_dir/$url/";
    WikiCommons::makedir "$wiki_dir/$url/$wiki_result";
    WikiCommons::add_to_remove ("$wiki_dir/$url/$wiki_result", "dir");
    my $rel_path = $pages_toimp_hash->{$url}[$rel_path_pos];
    
    my ($wiki, $deployment, $wrong);
    my ($wiki_general_txt, $deployment_general_txt) = SC_general_info($url, $ftp_links);
    $wiki->{'0'} = $wiki_general_txt;
    $deployment->{'00 General Information'} = $deployment_general_txt if defined $deployment_general_txt;

    opendir(DIR, "$path_files/$rel_path") || die("Cannot open directory $path_files/$rel_path: $!.\n");
    my @files = grep { (!/^\.\.?$/) && -f "$path_files/$rel_path/$_" && /(\.rtf)|(\.doc)/i } readdir(DIR);
    closedir(DIR);

    foreach my $file (sort @files) {
	my $file = "$path_files/$rel_path/$file";
	my ($name,$dir,$suffix) = fileparse($file, qr/\.[^.]*/);
	my ($node, $title, $header);
	if ($suffix eq ".doc" || $suffix eq ".odt" || $suffix eq ".docx") {
	    my $info_crt_h = $pages_toimp_hash->{$url}[$svn_url_pos];
	    foreach my $key (keys %$info_crt_h) {
		next if $key eq "SC_info";
		if ($key =~ m/^([0-9]{1,}) $name$/) {
		    $node = $1;
		    $title = $name;
		    my $date = "";
		    $date = $info_crt_h->{$key}->{'date'} if defined $info_crt_h->{$key}->{'date'};
		    $date =~ s/T/\t/;
		    $date =~ s/.[0-9]{1,}Z$//i;
		    $header = "<center>\'\'\'This file was automatically imported from the following document: [[Media:$url $name.zip|$url $name.zip]]\'\'\'\n\n";
		    $header .= "The original document can be found at [$info_h->{$name}/$info_crt_h->{$key}->{'name'} this address]\n\nThe last update on this document was performed at $date.\n";
		    $header .= "</center>\n----\n\n";
		    last;
		}
	    }
	} elsif ($suffix eq ".rtf") {
	    $title = $name;
	    $title =~ s/^([0-9]{1,}) //;
	    $node = $1;
	    $header = "";
	} else {
	    LOGDIE "WTF?\n";
	}

	if (! defined $title) {
	    ERROR "No title for $name.\n";
	    $wrong = "yes";
	    last;
	}
	INFO "\tWork for $file.\n";
	my $wiki_txt = create_wiki("$url/$url $name", $file, "$url $name");
	if (! defined $wiki_txt ){
# 		$to_keep->{$url} = $pages_toimp_hash->{$url};
	    delete $pages_toimp_hash->{$url};
	    $wrong = "yes";
	    ERROR "Skip url $url\n";
	    last;
	}
	WikiCommons::add_to_remove("$wiki_dir/$url/$url $name", "dir");
	$wiki_txt =~ s/\n(=+)(.*?)(=+)\n/\n=$1$2$3=\n/g;
	$deployment->{$title} = WikiClean::get_deployment_conf($wiki_txt) if $title ne "STP document";

	my $count = 0;
	if ($name !~ m/(review document)|(review docuemnt)/) {
	    my $newwiki = $wiki_txt;
	    my $q ="";
	    my $menu_h = {};
	    while ($wiki_txt =~ m/\n(==+)(.*?)(==+)\n/g ) {
		my $found_string = $&;
		my $length1 = length($1); my $length2 = length($3); my $menu_name = $2;
		foreach my $key (keys %$menu_h) {
		    delete $menu_h->{$key} if ( $key >= $length1+1 );
		}

		if ( exists $menu_h->{$length1} ) {
		    $menu_h->{$length1}++ ;
		} else {
		    $menu_h->{$length1} = 1;
		}

		$q = "";
		foreach my $key (sort {$a<=>$b} keys %$menu_h) {
		    $q .= $menu_h->{$key}.".";
		}
		$q .= " ";
		my $found_string_end_pos = pos($wiki_txt);
		substr($newwiki, $found_string_end_pos - length($found_string) + $count, length($found_string)) = "\n\'\'\'$q$menu_name\'\'\'\n";
		$count += 6 - ( $length1 + $length2 ) + length($q) * 1;
	    }
	    $wiki_txt = $newwiki;
	} else {
	    $wiki_txt =~ s/\n(==+)(.*?)(==+)\n/\n\'\'\'$2\'\'\'\n/g;
	    $count += 6 - ( length($1) + length($3) ) if defined $1 && defined $3;
	}

	$wiki_txt =~ s/^\s*(.*)\s*$/$1/gs;
	next if $wiki_txt eq '';
	$wiki_txt = "\n=$title=\n\n".$header.$wiki_txt."\n\n";
	$wiki->{$node} = $wiki_txt;

	### from dir $url/$doc$type/$wiki_result get all files in $url/$wiki_result
	WikiCommons::add_to_remove("$wiki_dir/$url/$wiki_result", "dir");
	WikiCommons::copy_dir ("$wiki_dir/$url/$url $name/$wiki_result", "$wiki_dir/$url/$wiki_result") if ($suffix eq ".doc");
    }

    if (defined $wrong && $wrong eq "yes"){
	my $name_bad = "$bad_dir/$url".time();
	WikiCommons::move_dir("$path_files/$rel_path", "$name_bad");
	$wrong_hash->{$url} = 1;
	exit 20;
    }

    my $dir = "$wiki_dir/$url/$wiki_result";
    opendir(DIR, $dir);
    @files = grep { (!/^\.\.?$/) && -f "$dir/$_" } readdir(DIR);
    closedir(DIR);
    if ( @files ) {
	my $files = join "\nFile:", @files;
	WikiCommons::write_file("$wiki_dir/$url/$wiki_files_uploaded", "File:$files\n");
    } else {
	WikiCommons::write_file("$wiki_dir/$url/$wiki_files_uploaded", "");
    }
    my $is_canceled = 0;
    $is_canceled++ if $pages_toimp_hash->{$url}[$svn_url_pos]->{'SC_info'}->{'revision'} =~ m/Cancel/i;
# print Dumper($pages_toimp_hash->{$url}, $is_canceled,$pages_toimp_hash->{$url}[$svn_url_pos]->{'SC_info'}->{'revision'});exit 1;

    my $url_deployment = $url;
    $url_deployment =~ s/^SC:/SC_Deployment:/;
    $our_wiki->wiki_delete_page ($url_deployment) if ( $our_wiki->wiki_exists_page($url_deployment) && $delete_previous_page ne "no");
    my $deployment_txt;
# INFO Dumper($deployment);exit 1;
    foreach my $doc_type (sort keys %$deployment) {
      my $used_name = $doc_type;
      $used_name =~ s/^[0-9]+\s*//;
      my $txt = $deployment->{$doc_type};
      next if ! defined $txt;
      $txt =~ s/(\n+|^)(=+)(.*?)(=+)\n/\n<b>$3 - [[$url#$used_name|$used_name]]<\/b>\n/ms;
      $txt =~ s/\n(=+)(.*?)(=+)\n/\n<b>$2<\/b>\n/gms;
      $deployment_txt .= "$txt\n\n";
    }

    my $full_wiki = "";
    $wiki->{0} =~ s/('''Parent ID''')/You can find auto generated deployment considerations '''[[$url_deployment|here]]'''\n\n$1/ms if (defined $deployment_txt && ! $is_canceled && ! defined $deployment_general_txt);
    $full_wiki .= $wiki->{$_} foreach (sort {$a<=>$b} keys %$wiki);
    WikiCommons::write_file("$wiki_dir/$url/$url.wiki", "$full_wiki");
    insertdata($url, $full_wiki);

    if (defined $deployment_txt && ! $is_canceled ) {
	my $title = $full_wiki;
	$title =~ s/^<center><font size="[0-9]{1,}">'''(.*?)'''<\/font><\/center>.*$/$1/gsi;
	my $url_s = $url; $url_s =~ s/^SC:(.*)/$1/;
	$deployment_txt = "=<small>[[SC:$url_s|$url_s: $title]]</small>=\n".$deployment_txt;
	INFO "\tImporting url $url_deployment.\t". (WikiCommons::get_time_diff) ."\n";
	$our_wiki->wiki_edit_page($url_deployment, $deployment_txt);
	LOGDIE "Could not import url $url_deployment.\t". (WikiCommons::get_time_diff) ."\n" if ( ! $our_wiki->wiki_exists_page($url_deployment) );
    }
    make_redirect($url, $wrong_hash);
    }; ## eval
    if ($@ && $@ !~ m/^Exiting eval via next at/) {
	ERROR "Error generating sc for $url: $@\n";
	exit 10;
    }
    exit 0;
}

sub getCommonInfoSC {
    my $info_h = {};
    open(FH, "$path_files/common_info") || die("Could not open file common_info: $!\n");
    my @info = <FH>;
    chomp @info;
    close (FH);

    foreach my $line (@info) {
	my @tmp = split ' = ', $line;
	$info_h->{$tmp[0]} = "$tmp[1]";
    }

    my $ftp_links = {};
    $ftp_links->{'FTP_def_attach'} = "ftp://$info_h->{'FTP_USER'}:$info_h->{'FTP_PASS'}\@$info_h->{'FTP_IP'}/$info_h->{'FTP_def_attach'}";
    $ftp_links->{'FTP_market_attach'} = "ftp://$info_h->{'FTP_USER'}:$info_h->{'FTP_PASS'}\@$info_h->{'FTP_IP'}/$info_h->{'FTP_market_attach'}";
    $ftp_links->{'FTP_test_attach'} = "ftp://$info_h->{'FTP_USER'}:$info_h->{'FTP_PASS'}\@$info_h->{'FTP_IP'}/$info_h->{'FTP_test_attach'}";
    return ($ftp_links, $info_h);
}

# quick_and_dirty_html_to_wiki
sub quick_and_dirty_html_to_wiki {
    my $url = "SIP Call Flow";
    my $work_dir = "$wiki_dir/$url";
    $wiki_result = "result";
    my $dest = "$work_dir/$wiki_result";
    WikiCommons::makedir ("$dest");
    `cp -R "./tmp/SIP Call Flow/"* "$work_dir"`;
    my $html_file = "$work_dir/article.asp.htm";

    my ($name,$dir,$suffix) = fileparse($html_file, qr/\.[^.]*/);
    my $zip_name = $name;
    my ($wiki, $image_files) = WikiClean::make_wiki_from_html ( $html_file );
    return undef if (! defined $wiki );


    WikiCommons::add_to_remove ("$work_dir/$wiki_result", "dir");
    WikiCommons::makedir ("$dest");
    my %seen = ();
    open (FILE, ">>$work_dir/$wiki_files_uploaded") or LOGDIE "at create wiki can't open file $work_dir/$wiki_files_uploaded for writing: $!\t". (WikiCommons::get_time_diff) ."\n";
    INFO "\t-Moving pictures and making zip file.\t". (WikiCommons::get_time_diff) ."\n";
    foreach my $img (@$image_files){
	move ("$img", "$dest") or LOGDIE "Moving file \"$img\" failed: $!\t". (WikiCommons::get_time_diff) ."\n" unless $seen{$img}++;
	my ($img_name,$img_dir,$img_suffix) = fileparse($img, qr/\.[^.]*/);
	print FILE "File:$img_name$img_suffix\n";
    }
    $image_files = ();

    my $zip = Archive::Zip->new();
    $zip->addFile( "$work_dir/$name$suffix", "$name$suffix") or LOGDIE "Error adding file $name$suffix to zip.\t". (WikiCommons::get_time_diff) ."\n";
    LOGDIE "Write error for zip file.\t". (WikiCommons::get_time_diff) ."\n" if $zip->writeToFileNamed( "$dest/$zip_name.zip" ) != AZ_OK;
    print FILE "File:$zip_name.zip\n";
    close (FILE);
    INFO "\t+Moving pictures and making zip file.\t". (WikiCommons::get_time_diff) ."\n";
    WikiCommons::add_to_remove( $html_file, "file" );

    $pages_toimp_hash->{$url}[$md5_pos] = "";
    $pages_toimp_hash->{$url}[$rel_path_pos] = "";
    $pages_toimp_hash->{$url}[$svn_url_pos] = "";
    $pages_toimp_hash->{$url}[$link_type_pos] = "";
    insertdata($url, $wiki);
    LOGDIE "Failed in cleanup.\n" if WikiCommons::cleanup($work_dir);
}

sub cleanAndExit {
    WARN "Killing all child processes\n";
    kill 9, map {s/\s//g; $_} split /\n/, `ps -o pid --no-headers --ppid $$`;
    exit 1000;
}

use sigtrap 'handler' => \&cleanAndExit, 'INT', 'ABRT', 'QUIT', 'TERM';

if (-f "$pid_file") {
    open (FH, "<$pid_file") or LOGDIE "Could not read file $pid_file.\n";
    my @info = <FH>;
    close (FH);
    chomp @info;
    $pid_old = $info[0];
    my $exists = kill 0, $pid_old if defined $pid_old && $pid_old =~ m/^[0-9]+$/;
    if ( $exists ) {
	my $proc_name = `ps -p $pid_old -o cmd`;
# 	print "$proc_name\n";
	LOGDIE "Process is already running.\n" if $proc_name =~ m/(.+?)generate_wiki\.pl -d (.+?) -n $path_type(.*)/;
# 	exit 1 if $proc_name =~ m/(.+?)generate_wiki\.pl -d (.+?) -n $path_type(.*)/;
    }
}
WikiCommons::write_file($pid_file,"$$\n");

$our_wiki = new WikiWork();
if ($path_type eq "mind_svn") {
    $lo_user = "wiki_svn";
    $coco = new WikiMindSVN($path_files);
    work_begin();
    work_for_docs();
} elsif ($path_type eq "cms_svn") {
    $lo_user = "wiki_cms";
    $coco = new WikiMindCMS($path_files);
    work_begin();
    work_for_docs();
} elsif ($path_type eq "users") {
    $lo_user = "wiki";
    $coco = new WikiMindUsers($path_files);
    work_begin();
    work_for_docs();
} elsif ($path_type =~ m/^crm_(.+)$/) {
    $lo_user = "";
    $coco = new WikiMindCRM("$path_files", "$1");
    $all_real = "yes";
    work_begin();
    make_categories();
    split_redirects();
    fork_function($crm_nr_forks, \&crm_worker);
} elsif ($path_type eq "sc_docs") {
    $lo_user = "wiki_sc";
    $coco = new WikiMindSC("$path_files", WikiCommons::get_urlsep);
    $all_real = "yes";
    work_begin();
    make_categories();
    split_redirects();
    foreach (keys %$pages_toimp_hash) {LOGDIE "There are no links.\n" if ($pages_toimp_hash->{$_}[$link_type_pos] eq "link")};
    fork_function($sc_nr_forks, \&sc_worker, getCommonInfoSC());
}

@tmp = (sort keys %$failed);
# ERROR "Failed:\n".Dumper(@tmp) if @tmp;
foreach (@tmp) {
    my $sth_mysql = $dbh_mysql->do("DELETE FROM mind_wiki_info where WIKI_NAME=".$dbh_mysql->quote($_));
    ERROR "Failed: $_\n"
}
$dbh_mysql->disconnect() if defined($dbh_mysql);
@crt_timeData = localtime(time);
foreach (@crt_timeData) {$_ = "0$_" if($_<10);}
INFO "End ". ($crt_timeData[5]+1900) ."-$crt_timeData[4]-$crt_timeData[3] $crt_timeData[2]:$crt_timeData[1]:$crt_timeData[0].\n";
unlink("$pid_file") or LOGDIE "Could not delete the file $pid_file: ".$!."\n";
