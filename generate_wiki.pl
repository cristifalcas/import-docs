#!/usr/bin/perl -w
print "Start.\n";

#soffice "-accept=socket,host=localhost,port=2002;urp;StarOffice.ServiceManager" -nologo -headless -nofirststartwizard

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

die "We need the dir where the doc files are and the type of the dir: mind_svn, users, sc_docs.\n" if ( $#ARGV != 1 );

use warnings;
use strict;

use Cwd 'abs_path';
use File::Basename;
use File::Copy;
use File::Find;
use Switch;

use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."./our_perl_lib/lib";

use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use HTML::WikiConverter;
use Data::Dumper;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Text::Balanced;
use Encode;
use URI::Escape;
use File::Path qw(make_path remove_tree);

use Mind_work::WikiWork;
use Mind_work::WikiCommons;
use Mind_work::WikiClean;
use Mind_work::WikiMindUsers;
use Mind_work::WikiMindSVN;
use Mind_work::WikiMindSC;

my $our_wiki;

my $path_prefix = "/media/share/Documentation/cfalcas/q/import_docs";
# my $path_prefix = "./";
my $path_files = abs_path(shift);
my $path_type = shift;
our $wiki_dir = "$path_prefix/work/workfor_". (fileparse($path_files, qr/\.[^.]*/))[0] ."";
WikiCommons::makedir $wiki_dir;
$wiki_dir = abs_path($wiki_dir);

my $bad_dir = "$path_prefix/work/bad_dir";
my $pid_file = "$path_prefix/work/mind_import_wiki.pid";
my $remote_work_path = "./remote_batch_files";

my $wiki_result = "result";
my $wiki_files_uploaded = "wiki_files_uploaded.txt";
my $wiki_files_info = "wiki_files_info.txt";

my $delete_everything = "no";
my $delete_categories = "no";
my $make_categories = "no";
my $pid_old = "100000";
my $all_real = "no";
my $type_old = "";

my $pages_toimp_hash = {};
my $pages_local_hash = {};

my $md5_pos = 0;
my $rel_path_pos = 1;
my $svn_url_pos = 2;
my $link_type_pos = 3;
my $categories_pos = 4;

my $count_files;
our $coco;
WikiCommons::is_remote("no");

sub create_wiki {
    my ($page_url, $doc_file, $zip_name) = @_;
    die "Page url is empty.\n" if $page_url eq '';
    $zip_name = $page_url if ! defined $zip_name;
    my $work_dir = "$wiki_dir/$page_url";
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
    if ( -d $work_dir) {
	print "Path $work_dir already exists. Moving to $bad_dir.\t". (WikiCommons::get_time_diff) ."\n" ;
	my $name_bad = "$bad_dir/$page_url".time();
	WikiCommons::makedir("$name_bad");
	move("$work_dir","$name_bad");
	die "Directory still exists." if ( -d $work_dir);
    }
    WikiCommons::makedir ("$work_dir");
    $name = WikiCommons::normalize_text($name);

    copy("$doc_file","$work_dir/$name$suffix") or die "Copy failed at create_wiki: $doc_file to $work_dir: $!\t". (WikiCommons::get_time_diff) ."\n";
    $doc_file = "$work_dir/$name$suffix";

    if ( -f $doc_file ) {
	WikiCommons::generate_html_file($doc_file);
	my $html_file = "$work_dir/$name.html";

	if ( -f $html_file && ! -e ".~lock.$name.$suffix#") {
	    my ($wiki, $image_files) = WikiClean::make_wiki_from_html ( $html_file );
	    my $dest = "$work_dir/$wiki_result";
	    WikiCommons::add_to_remove ("$work_dir/$wiki_result", "dir");
	    WikiCommons::makedir ("$dest");

	    my %seen = ();
	    open (FILE, ">>$work_dir/$wiki_files_uploaded") or die "at create wiki can't open file $work_dir/$wiki_files_uploaded for writing: $!\t". (WikiCommons::get_time_diff) ."\n";
	    print "\t-Moving pictures and making zip file.\t". (WikiCommons::get_time_diff) ."\n";
	    foreach my $img (@$image_files){
		move ("$img", "$dest") or die "Moving file \"$img\" failed: $!\t". (WikiCommons::get_time_diff) ."\n" unless $seen{$img}++;
		my ($img_name,$img_dir,$img_suffix) = fileparse($img, qr/\.[^.]*/);
		print FILE "File:$img_name$img_suffix\n";
	    }
	    $image_files = ();

	    my $zip = Archive::Zip->new();
	    $zip->addFile( "$work_dir/$name$suffix", "$name$suffix") or die "Error adding file $name$suffix to zip.\t". (WikiCommons::get_time_diff) ."\n";
	    die "Write error for zip file.\t". (WikiCommons::get_time_diff) ."\n" if $zip->writeToFileNamed( "$dest/$zip_name.zip" ) != AZ_OK;
	    print FILE "File:$zip_name.zip\n";
	    close (FILE);
	    print "\t+Moving pictures and making zip file.\t". (WikiCommons::get_time_diff) ."\n";

# 	    opendir(DIR,$work_dir) || die("Cannot open directory $work_dir.\n");
# 	    my @files = readdir(DIR);
# 	    closedir(DIR);
# 	    foreach(@files) {
# 		die "Extra files in $work_dir:$_.\n" if (-f $_);
# 	    }

	    WikiCommons::add_to_remove( $doc_file, "file" );
	    WikiCommons::add_to_remove( $html_file, "file" );
	    return $wiki;
	} else {
	    die "OpenOffice could not create the html file.\t". (WikiCommons::get_time_diff) ."\n";
	}
	} else {
	die "Strange, can't find the doc file in $work_dir.\t". (WikiCommons::get_time_diff) ."\n";
    }
}

sub get_existing_pages {
    opendir(DIR, "$wiki_dir") || die("Cannot open directory $wiki_dir.\n");
    my @allfiles = grep { (!/^\.\.?$/) && -d "$wiki_dir/$_" } readdir(DIR);
    closedir(DIR);
    $_ = "$wiki_dir/".$_ foreach (@allfiles);

    $count_files = 0;
    print "-Searching for files in local dir.\t". (WikiCommons::get_time_diff) ."\n";
    foreach my $dir (sort @allfiles) {
	if (-d "$dir") {
	    next if ($dir eq "$wiki_dir/categories");
	    if ( -f "$dir/$wiki_files_info" && -f "$dir/$wiki_files_info") {
		open(FILE, "$dir/$wiki_files_info");
		my @info_text = <FILE>;
		close FILE;
		chomp(@info_text);
		if ( @info_text != 4 ) {
		    print "\tFile $dir/$wiki_files_info does not have the correct number of entries.\n";
		    next;
		}
		my $md5 = (split ('=', $info_text[$md5_pos]))[1];
		my $rel_path = (split ('=', $info_text[$rel_path_pos]))[1];
		my $svn_url = (split ('=', $info_text[$svn_url_pos]))[1];
		my $url_type = (split ('=', $info_text[$link_type_pos]))[1];
		if (!(defined $md5 && defined $rel_path && defined $url_type && defined $svn_url)){
		    print "\tFile $dir/$wiki_files_info does not have the correct information.\n";
		    next;
		}
		$md5 =~ s/(^\s+|\s+$)//g;
		$rel_path =~ s/(^\s+|\s+$)//g;
		$svn_url =~ s/(^\s+|\s+$)//g;
		$url_type =~ s/(^\s+|\s+$)//g;
		die "\tWe already have this url. But this is insane...\t". (WikiCommons::get_time_diff) ."\n" if (exists $pages_toimp_hash->{$dir});
		my ($name,$dir,$suffix) = fileparse($dir, qr/\.[^.]*/);
		$pages_local_hash->{"$name$suffix"} = [$md5, $rel_path, $svn_url, $url_type, []];
		++$count_files;
	    } else {
		print "\tThis is not a correct wiki dir: $dir\n";
		my @q = split '/', $dir;
		my $name_bad = "$bad_dir/$q[$#q]".time();
		WikiCommons::makedir("$name_bad");
		move("$dir","$name_bad");
		die "\tDirectory still exists." if ( -d $dir);
	    }
	} else {
	    print "\tExtra files in wiki dir: $dir\n";
	}
    }
    print "\tTotal number of files: ".($count_files)."\t". (WikiCommons::get_time_diff) ."\n";
    print "+Searching for files in local dir.\t". (WikiCommons::get_time_diff) ."\n";
}

sub generate_new_updated_pages {
    my ($to_delete, $to_keep) = @_;
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
		print "Delete url $url because: \n\t\tcrt_md5 $pages_local_hash->{$url}[$md5_pos] <> $pages_toimp_hash->{$url}[$md5_pos] or \n\t\tcrt_rel_path $pages_local_hash->{$url}[$rel_path_pos] <> $pages_toimp_hash->{$url}[$rel_path_pos].\n";
	    } else {
		print "Delete url $url because it doesn't exist anymore.\n";
	    }
	    $to_delete->{$url} = $pages_local_hash->{$url};
	}
    }
    return ($to_delete, $to_keep);
}

sub generate_real_and_links {
    my ($to_delete, $to_keep) = @_;
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
		print "Remove link url $url because of all links: $nr_link.\n";
		$to_delete->{$url} = $to_keep->{$url} if (exists $to_keep->{$url});
		$pages_toimp_hash->{$url} = $to_keep->{$url} if (exists $to_keep->{$url});
		delete($to_keep->{$url});
	    }
	}
	if ( $nr_real > 1 ) {
	    my $q = $md5_map->{$md5}{"real"};
	    for (my $i=0; $i < $nr_real - 1; $i++) {
		print "Remove real url @$q[$i]} because of too many real links: $nr_real.\n";
		print Dumper(@$q[$i]);
		$to_delete->{@$q[$i]} = $to_keep->{@$q[$i]};
		$pages_toimp_hash->{@$q[$i]} = $to_keep->{@$q[$i]};
		delete($to_keep->{@$q[$i]});
		$pages_toimp_hash->{@$q[$i]}[$link_type_pos] = "link";
	    }
	    $q = $md5_map->{$md5}{"link"};
	    foreach my $url (@$q) {
		print "Remove link url $url because of too many real links: $nr_real.\n";
		$to_delete->{$url} = $to_keep->{$url} if (exists $to_keep->{$url});
		$pages_toimp_hash->{$url} = $to_keep->{$url} if (exists $to_keep->{$url});
		$pages_toimp_hash->{$url}[$link_type_pos] = "link";
		delete($to_keep->{$url});
	    }
	}
    }
    return ($to_delete, $to_keep);
}

sub generate_cleaned_real_and_links {
    my $to_keep = shift;
    ## for all pages that need to be imported, make one real and let all the rest links
    my $md5_map = {};
    my $md5_map_keep = {};
    return if ($all_real eq "yes");
    print "\tstart checking for links.\n";
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
	print "done $count out of $total.\t". (WikiCommons::get_time_diff) ."\n" if ++$count%1000 == 0;
    }
#     return ($to_delete, $to_keep);
}

sub generate_pages_to_delete_to_import {
    my ( $to_delete, $to_keep ) = @_;
    print "Start generating new/updated/to_delete/to_keep urls.\t". (WikiCommons::get_time_diff) ."\n";
    ($to_delete, $to_keep) = generate_new_updated_pages($to_delete, $to_keep);
    print "Done generating new/updated urls.\t". (WikiCommons::get_time_diff) ."\n";
    ($to_delete, $to_keep) = generate_real_and_links($to_delete, $to_keep);
    print "Done separating urls in real and links.\t". (WikiCommons::get_time_diff) ."\n";
#     ($to_delete, $to_keep) = generate_cleaned_real_and_links($to_delete, $to_keep);
    generate_cleaned_real_and_links($to_keep);
    print "Done final cleaning of urls.\t". (WikiCommons::get_time_diff) ."\n";

    my $tmp = {};
    foreach (keys %$pages_toimp_hash) {$tmp->{$_} = 1 if ($pages_toimp_hash->{$_}[$link_type_pos] eq "link")};

    print "1. Number of files to import: ",scalar keys %$pages_toimp_hash,"\n";
    print "2. Number of files to import as links: ",scalar keys %$tmp,"\n";
    print "3. Number of files already imported: ",scalar keys %$to_keep,"\n";
    print "4. Number of files to delete: ",scalar keys %$to_delete,"\n";

    return $to_delete, $to_keep;
}

sub delete_categories {
    my $categories_dir = "$wiki_dir/categories/";
    my @files = ();
    if (-e "$wiki_dir/categories/") {
	opendir(DIR, "$categories_dir") || die("Cannot open directory $categories_dir.\n");
	@files = grep { (!/^\.\.?$/) && -d "$categories_dir/$_" } readdir(DIR);
	closedir(DIR);
    }
    foreach my $category (@files) {
	print "-Delete category $category.\t". (WikiCommons::get_time_diff) ."\n";
	if ( -d "$categories_dir/$category" ) {
	    my ($name,$dir,$suffix) = fileparse("$categories_dir/$category", qr/\.[^.]*/);
	    $our_wiki->wiki_delete_page("$name$suffix", "") if ( $our_wiki->wiki_exists_page("$name$suffix") );
	    remove_tree("$dir$name$suffix") || die "Can't remove dir $dir$name$suffix: $?.\n";
	} else {
	    print "Extra file in $categories_dir: $categories_dir/$category.\n";
	}
	print "+Delete category $category.\t". (WikiCommons::get_time_diff) ."\n";
    }
}

sub make_categories {
    return 1 if ( $make_categories eq "no");
    my $url = "";
    delete_categories if ( $delete_categories eq "yes");

    return if ($delete_everything eq "yes");
    print "-Making categories.\t". (WikiCommons::get_time_diff) ."\n";
    my $general_categories_hash = WikiCommons::get_categories;
    foreach my $key (sort keys %$general_categories_hash) {
	my $text = "----\n\n";
	$url = "Category:$key";
	foreach my $sec_key (sort keys %{$general_categories_hash->{$key}} ) {
	    $text .= "\[\[Category:$sec_key\]\]\n"
	}

	if ( $our_wiki->wiki_exists_page($url) ) {
	    my $page = $our_wiki->wiki_get_page($url);
	    while ($page =~ m/\[\[Category:(.*?)\]\]/gi ) {
		my $q = $1;
		my $w = quotemeta $q;
		$text .= "\[\[Category:$q\]\]\n" if ($text !~ m/\[\[Category:$w\]\]/);
	    }
	}
	$text .= "----\n\n";

	$our_wiki->wiki_edit_page($url, $text);
	die "Could not import url $url.\t". (WikiCommons::get_time_diff) ."\n" if ( ! $our_wiki->wiki_exists_page($url) );
	my $work_dir = "$wiki_dir/categories/$url";
	WikiCommons::makedir("$work_dir");
	WikiCommons::write_file ("$work_dir/$wiki_files_info", "md5 = 0\nrel_path = 0\nsvn_url = 0\nlink_type = category\n");

	print "Done $url.\t". (WikiCommons::get_time_diff) ."\n";
    }
    print "+Making categories.\t". (WikiCommons::get_time_diff) ."\n";
}

sub insertdata {
    my ($url, $wiki) = @_;
    my $work_dir = "$wiki_dir/$url";
    WikiCommons::write_file("$work_dir/$url.full.wiki", $wiki, 1);

    if (WikiCommons::is_remote ne "yes"){
	$our_wiki->wiki_import_files ("$work_dir/$wiki_result", "$url");
	print "\tDeleting url $url just to be sure.\t". (WikiCommons::get_time_diff) ."\n";
	$our_wiki->wiki_delete_page ($url,"") if ( $our_wiki->wiki_exists_page($url) );
	print "\tImporting url $url.\t". (WikiCommons::get_time_diff) ."\n";
	$our_wiki->wiki_edit_page($url, $wiki);
	die "Could not import url $url.\t". (WikiCommons::get_time_diff) ."\n" if ( ! $our_wiki->wiki_exists_page($url) );
	print "\tDone $url.\t". (WikiCommons::get_time_diff) ."\n";
    } else {
	print "\tCopy files to $remote_work_path/$wiki_result\n";
	WikiCommons::makedir("$remote_work_path/$wiki_result");
	WikiCommons::copy_dir ("$work_dir/$wiki_result", "$remote_work_path/$wiki_result");
	copy("$work_dir/$url.full.wiki","$remote_work_path/$url.wiki") or die "Copy failed for: $url.full.wiki to $remote_work_path: $!\t". (WikiCommons::get_time_diff) ."\n";
    }

    my $text = "md5 = $pages_toimp_hash->{$url}[$md5_pos]\n";
    $text .= "rel_path = $pages_toimp_hash->{$url}[$rel_path_pos]\n";
    $text .= "svn_url = $pages_toimp_hash->{$url}[$svn_url_pos]\n";
    $text .= "link_type = $pages_toimp_hash->{$url}[$link_type_pos]\n";
    WikiCommons::write_file("$work_dir/$wiki_files_info", $text);
    delete($pages_toimp_hash->{$url});
    WikiCommons::cleanup;
}

sub work_real {
    my ($to_keep, $path_files) = @_;
    foreach my $url (sort keys %$pages_toimp_hash) {
	next if ($pages_toimp_hash->{$url}[$link_type_pos] eq "link");
	WikiCommons::reset_time();
	print "\n*************************\nMaking real url for $url\n\t\t$path_files/$pages_toimp_hash->{$url}[$rel_path_pos].\t". (WikiCommons::get_time_diff) ."\n";
	my $svn_url = $pages_toimp_hash->{$url}[$svn_url_pos];
	$svn_url = uri_escape( $svn_url,"^A-Za-z\/:0-9\-\._~%" );
	my $wiki = create_wiki($url, "$path_files/$pages_toimp_hash->{$url}[$rel_path_pos]");
	my $head_text = "<center>\'\'\'This file was automatically imported from the following document: [[File:$url.zip|$url.zip]]\'\'\'\n\n";
	$head_text .= "The original document can be found at [$svn_url this address]\n" if ($svn_url ne "");
	$head_text .= "</center>\n----\n\n\n\n\n\n".$wiki."\n----\n\n";
	$wiki = $head_text;
	my $cat = $pages_toimp_hash->{$url}[$categories_pos];
	foreach (@$cat) {
	    $wiki = $wiki."[[Category:$_]]" if ($_ ne "");
	}

	$to_keep->{$url} = $pages_toimp_hash->{$url};
	my ($name,$dir,$suffix) = fileparse($path_files."/".$pages_toimp_hash->{$url}[$rel_path_pos], qr/\.[^.]*/);
	insertdata($url, $wiki);
	if ($path_type eq "users"){
	    my $text_url = "[InternetShortcut]\nURL=". $our_wiki->wiki_geturl ."/index.php/$url";
	    WikiCommons::write_file ("$dir/$name.url", $text_url);
	}
    }
}

sub work_link {
    my $to_keep = shift;
    ## presumbly we have now only links
    my $md5_map = {};
    push @{$md5_map->{$to_keep->{$_}[$md5_pos]}{$to_keep->{$_}[$link_type_pos]}}, ($_) foreach (keys %$to_keep);
    foreach my $md5 (keys %$md5_map) {
	my $nr_real = scalar @{ $md5_map->{$md5}{"real"} } if (exists $md5_map->{$md5}{"real"});
	my $nr_link = scalar @{ $md5_map->{$md5}{"link"} } if (exists $md5_map->{$md5}{"link"});
	die "We should only have ONE real link: real=$nr_real link=$nr_link.\n" if ($nr_real != 1 && $nr_link != 0);
    }

    foreach my $url (sort keys %$pages_toimp_hash) {
	WikiCommons::reset_time();
	print "\n*************************\nMaking link for url $url\n\t\t$path_files/$pages_toimp_hash->{$url}[$rel_path_pos].\t". (WikiCommons::get_time_diff) ."\n";
	my $link_to = $md5_map->{$pages_toimp_hash->{$url}[$md5_pos]}->{"real"}[0];
	die "We should have a url in to_keep.\n" if (scalar @{$pages_toimp_hash->{$url}} != scalar @{$to_keep->{$link_to}});
	my ($link_name,$link_dir,$link_suffix) = fileparse($to_keep->{$link_to}[$rel_path_pos], qr/\.[^.]*/);
	my ($name,$dir,$suffix) = fileparse($pages_toimp_hash->{$url}[$rel_path_pos], qr/\.[^.]*/);
	my $link_file = "$wiki_dir/$link_to/$link_name.wiki";
	WikiCommons::makedir("$wiki_dir/$url/");
	WikiCommons::write_file("$wiki_dir/$url/$wiki_files_uploaded", "");
	copy("$link_file","$wiki_dir/$url/$name.wiki") or die "Copy failed for link: $link_file to $wiki_dir/$url: $!\t". (WikiCommons::get_time_diff) ."\n";
	open (FILEHANDLE, "$wiki_dir/$url/$name.wiki") or die $!."\t". (WikiCommons::get_time_diff) ."\n";
	my $wiki = do { local $/; <FILEHANDLE> };
	close (FILEHANDLE);

	my $svn_url = $pages_toimp_hash->{$url}[$svn_url_pos];
	$svn_url = uri_escape( $svn_url,"^A-Za-z\/:0-9\-\._~%" );

	my $head_text = "<center>\'\'\'This file was shamesly copied from the following url: [[$link_to]] because the doc files are identical.\'\'\'\n\n";
	$head_text .= "The original document can be found at [$svn_url this address]\n" if ($svn_url ne "");
	$head_text .= "</center>\n----\n\n\n\n\n\n".$wiki."\n----\n\n";
	$wiki = $head_text;
	my $cat = $pages_toimp_hash->{$url}[$categories_pos];
	foreach (@$cat) {
	    $wiki = $wiki."[[Category:$_]]" if ($_ ne "");
	}
	insertdata($url, $wiki);
    }
}

sub work_begin {
    WikiCommons::reset_time();
    get_existing_pages;

    my ($to_delete, $to_keep) = {};
    if ($delete_everything eq "yes") {
	$to_delete->{$_} = $pages_local_hash->{$_} foreach (sort keys %$pages_local_hash);
	$pages_toimp_hash = {};
    } else {
	$pages_toimp_hash = $coco->get_documents();
	($to_delete, $to_keep) = generate_pages_to_delete_to_import;
    }

    if (WikiCommons::is_remote ne "yes") {
	foreach my $url (sort keys %$to_delete) {
	    print "Deleting $url.\t". (WikiCommons::get_time_diff) ."\n";
	    $our_wiki->wiki_delete_page($url, "$wiki_dir/$url/$wiki_files_uploaded") if ( $our_wiki->wiki_exists_page($url) );
	    remove_tree("$wiki_dir/$url") || die "Can't remove dir $wiki_dir/$url: $?.\n";
	}
    }
    return ($to_delete, $to_keep);
}

sub work_for_docs {
    my ($path_files) = @_;
    my ($to_delete, $to_keep) = work_begin;
    make_categories;
    work_real($to_keep, $path_files);
    work_link($to_keep);
}

# 	my @oo_procs = `ps -ef | grep office | grep -v grep`;
# 	die "OpenOffice is already running.\n" if (@oo_procs);
# 	my $result = `/usr/bin/ooffice "$doc_file" -headless -invisible "macro:///Standard.Module1.runall()"`;
# my @oo_procs = `ps -ef | grep '\\-accept=socket,host=127.0.0.1,port=2002;urp;StarOffice.ServiceManager' | grep -v grep`;
# die "OpenOffice is NOT running: $#oo_procs.\t". (WikiCommons::get_time_diff) ."\n" if ($#oo_procs < 1);

if (-f "$pid_file") {
    open (FH, "<$pid_file") or die "Could not read file $pid_file.\n";
    my @info = <FH>;
    close (FH);
    chomp @info;
    $pid_old = $info[0];
    $type_old = $info[1];
}
WikiCommons::write_file($pid_file,"$$\n$path_type\n");

$our_wiki = new WikiWork();
if ($path_type eq "mind_svn") {
    $coco = new WikiMindSVN("$path_files", WikiCommons::get_urlsep);
    work_for_docs("$path_files");
} elsif ($path_type eq "users") {
    $coco = new WikiMindUsers("$path_files", WikiCommons::get_urlsep);
    work_for_docs("$path_files");
} elsif ($path_type eq "sc_docs") {
    $all_real = "yes";
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

#     my $url_sep = WikiCommons::get_urlsep;
    $coco = new WikiMindSC("$path_files", WikiCommons::get_urlsep);
    my ($to_delete, $to_keep) = work_begin;
    make_categories;
    my $tmp = {};
    foreach (keys %$pages_toimp_hash) {$tmp->{$_} = 1 if ($pages_toimp_hash->{$_}[$link_type_pos] eq "link")};
    die "There are no links.\n" if scalar keys %$tmp;

    my $general_wiki_file = "General_info.wiki";
    foreach my $url (sort keys %$pages_toimp_hash) {
#     next if "$url" ne "SC:B91991";
	WikiCommons::reset_time();
	print "\n*************************\nMaking sc url for $url.\t". (WikiCommons::get_time_diff) ."\n";

	WikiCommons::makedir "$wiki_dir/$url/";
	WikiCommons::makedir "$wiki_dir/$url/$wiki_result";
	my $rel_path = "$pages_toimp_hash->{$url}[$rel_path_pos]";

	my $info_crt_h = $pages_toimp_hash->{$url}[$svn_url_pos];

	my $wiki = {};
	local( $/, *FH ) ;
	open(FH, "$path_files/$rel_path/$general_wiki_file") || die("Could not open file: $!");
	my $wiki_txt = <FH>;
	close (FH);
	$wiki_txt =~ s/^[\f ]+|[\f ]+$//mg;
	foreach my $key (keys %{$info_crt_h->{"Categories"}}) {
	    $wiki_txt.= "[[Category:".$info_crt_h->{'Categories'}->{$key}."]]" if $info_crt_h->{'Categories'}->{$key} ne "";
	}

	$wiki_txt .= "\n\n'''FTP links:'''\n\n";
	foreach my $key (keys %$ftp_links) {
	    $wiki_txt .= "[$ftp_links->{$key}/$rel_path $key]\n\n";
	}

	$wiki->{'0'} = $wiki_txt;

	opendir(DIR, "$path_files/$rel_path") || die("Cannot open directory $path_files/$rel_path: $!.\n");
	my @files = grep { (!/^\.\.?$/) && -f "$path_files/$rel_path/$_" && /(\.rtf)|(\.doc)/i } readdir(DIR);
	closedir(DIR);
	foreach my $file (@files) {
	    my $file = "$path_files/$rel_path/$file";
	    my ($name,$dir,$suffix) = fileparse($file, qr/\.[^.]*/);
	    my ($node, $title, $header) = "";
	    if ($suffix eq ".doc") {
		foreach my $key (keys %$info_crt_h) {
		    if ($key =~ m/^([0-9]{1,}) $name$/) {
			$node = $1;
			$title = $name;
			$header = "<center>\'\'\'This file was automatically imported from the following document: [[File:$url $name.zip]]\'\'\'\n\n";
			$header .= "The original document can be found at [$info_h->{$name}/$info_crt_h->{$key}->{'name'} this address]\n";
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
		die "WTF?\n";
	    }
	    print "\tWork for $file.\n";
	    my $wiki_txt = create_wiki("$url/$url $name", "$file", "$url $name");
	    WikiCommons::add_to_remove("$wiki_dir/$url/$url $name", "dir");
	    $wiki_txt =~ s/\n(=+)(.*?)(=+)\n/\n=$1$2$3=\n/g;

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
		$count += 6 - ( length($1) + length($1) );
	    }

	    $wiki_txt =~ s/^\s*(.*)\s*$/$1/gs;
	    next if $wiki_txt eq '';
	    die "No title for $name.\n" if ! defined $title;
	    $wiki_txt = "\n=$title=\n\n".$header.$wiki_txt."\n\n";
	    $wiki->{$node} = $wiki_txt;

	    ### from dir $url/$doc$type/$wiki_result get all files in $url/$wiki_result
	    WikiCommons::add_to_remove("$wiki_dir/$url/$wiki_result", "dir");
	    WikiCommons::copy_dir ("$wiki_dir/$url/$url $name/$wiki_result", "$wiki_dir/$url/$wiki_result") if ($suffix eq ".doc");
	}
	my $full_wiki = "";
	$full_wiki .= $wiki->{$_} foreach (sort {$a<=>$b} keys %$wiki);

	WikiCommons::write_file("$wiki_dir/$url/$url.wiki", "$full_wiki");

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

	insertdata($url, $full_wiki);
    }
}

print "End.\n";
unlink("$pid_file") or die "Could not delete the file $pid_file: ".$!."\n";
