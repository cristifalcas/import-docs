#!/usr/bin/perl -w
print "Start.\n";
use warnings;
use strict;
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
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Text::Balanced;
# use Encode;
use URI::Escape;
use File::Path qw(make_path remove_tree);

use Mind_work::WikiWork;
use Mind_work::WikiCommons;
use Mind_work::WikiClean;
use Mind_work::WikiMindUsers;
use Mind_work::WikiMindSVN;
use Mind_work::WikiMindSC;
use Mind_work::WikiMindCRM;
use Mind_work::WikiMindCMS;

# declare the perl command line flags/options we want to allow
my $options = {};
getopts("rd:n:c:", $options);

our $remote_work = "no";
if ($options->{'r'}){
    $remote_work = "yes";
}

my $delete_categories = "yes";
my $make_categories = "yes";
if (defined $options->{'c'}) {
    if ($options->{'c'} =~ m/^y$/i){
	$delete_categories = "yes";
	$make_categories = "yes";
    }
    if ($options->{'c'} =~ m/^n$/i){
	$delete_categories = "no";
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
my $wiki_files_info = "wiki_files_info.txt";

my $delete_everything = "no";
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
WikiCommons::is_remote("$remote_work");
WikiCommons::set_real_path($path_prefix);

sub create_wiki {
    my ($page_url, $doc_file, $zip_name) = @_;
    die "Page url is empty.\n" if $page_url eq '';
    $zip_name = $page_url if ! defined $zip_name;
    my $work_dir = "$wiki_dir/$page_url";

    my ($name_url,$dir_url,$suffix_url) = fileparse($page_url, qr/\.[^.]*/);
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
    if ( -d $work_dir) {
	print "Path $work_dir already exists. Moving to $bad_dir.\t". (WikiCommons::get_time_diff) ."\n" ;
	my $name_bad = "$bad_dir/$page_url".time();
	WikiCommons::makedir("$name_bad");
	move("$work_dir", "$name_bad") || die "Can't move dir $work_dir\n\tto $name_bad\n: $!.\n";
	die "Directory still exists." if ( -d $work_dir);
    }
    WikiCommons::makedir ("$work_dir");
    $name = WikiCommons::normalize_text($name);

    my $new_file = "$name_url$suffix_url";
    copy("$doc_file","$work_dir/$new_file$suffix") or die "Copy failed for $page_url at create_wiki: $doc_file to $work_dir: $!\t". (WikiCommons::get_time_diff) ."\n";
    $doc_file = "$work_dir/$new_file$suffix";

    if ( -f $doc_file ) {
	WikiCommons::generate_html_file($doc_file);
	my $html_file = "$work_dir/$new_file.html";

	if ( -f $html_file && ! -e ".~lock.$new_file#") {
	    my ($wiki, $image_files) = WikiClean::make_wiki_from_html ( $html_file );
	    return undef if (! defined $wiki );

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
	    $zip->addFile( "$work_dir/$new_file$suffix", "$new_file$suffix") or die "Error adding file $new_file$suffix to zip.\t". (WikiCommons::get_time_diff) ."\n";
	    die "Write error for zip file.\t". (WikiCommons::get_time_diff) ."\n" if $zip->writeToFileNamed( "$dest/$zip_name.zip" ) != AZ_OK;
	    print FILE "File:$zip_name.zip\n";
	    close (FILE);
	    print "\t+Moving pictures and making zip file.\t". (WikiCommons::get_time_diff) ."\n";

	    WikiCommons::add_to_remove( $doc_file, "file" );
	    WikiCommons::add_to_remove( $html_file, "file" );
	    return $wiki;
	} else {
	    print "OpenOffice could not create the html file.\t". (WikiCommons::get_time_diff) ."\n";
	    return;
	}
    } else {
	 print "Strange, can't find the doc file in $work_dir.\t". (WikiCommons::get_time_diff) ."\n";
	 return;
    }
}

sub get_existing_pages {
    opendir(DIR, "$wiki_dir") || die("Cannot open directory $wiki_dir.\n");
    my @allfiles = grep { (!/^\.\.?$/) && -d "$wiki_dir/$_" } readdir(DIR);
    closedir(DIR);
    $_ = "$wiki_dir/".$_ foreach (@allfiles);

    $count_files = 0;
    print "-Searching for files in local dir.\t". (WikiCommons::get_time_diff) ."\n";
    my $total = scalar @allfiles;
    my $crt_nr = 0;
    foreach my $dir (sort @allfiles) {
	if (-d "$dir") {
	    next if ($dir eq "$wiki_dir/categories");
	    $crt_nr++;
	    print "\tDone $crt_nr from a total of $total.\t". (WikiCommons::get_time_diff) ."\n" if ($crt_nr%100 == 0);
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
# 		$rel_path = Encode::decode ('utf8', $rel_path);
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
# 		WikiCommons::makedir("$name_bad");
		move("$dir","$name_bad") || die "Can't move dir $dir to $name_bad: $!.\n";;
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
# print Dumper($pages_local_hash->{$url});die;
		print "Url $url will be updated because: \n\t\tcrt_md5\n\t\t\t$pages_local_hash->{$url}[$md5_pos] <> \n\t\t\t$pages_toimp_hash->{$url}[$md5_pos] or \n\t\tcrt_rel_path \n\t\t\t$pages_local_hash->{$url}[$rel_path_pos] <> \n\t\t\t$pages_toimp_hash->{$url}[$rel_path_pos].\n";
	    } else {
		print "Delete url $url because it doesn't exist anymore.\n";
		$to_delete->{$url} = $pages_local_hash->{$url};
	    }
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
		print "Remove real url @$q[$i] because of too many real links: $nr_real.\n";
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
    my ( $to_delete, $to_keep ) = {};
    print "Start generating new/updated/to_delete/to_keep urls.\t". (WikiCommons::get_time_diff) ."\n";
    ($to_delete, $to_keep) = generate_new_updated_pages($to_delete, $to_keep);
    print "Done generating new/updated urls.\t". (WikiCommons::get_time_diff) ."\n";
    ($to_delete, $to_keep) = generate_real_and_links($to_delete, $to_keep);
    print "Done separating urls in real and links.\t". (WikiCommons::get_time_diff) ."\n";
#     ($to_delete, $to_keep) = generate_cleaned_real_and_links($to_delete, $to_keep);
    if ($path_type eq "sc_docs"){
	foreach my $url (keys %$pages_toimp_hash) {
	    if ($url =~ m/^SC_(.*)?:(.*)/) {
		my $new_delete = "SC:$2";
		if (exists $to_keep->{$new_delete} && ! defined $pages_toimp_hash->{$new_delete}) {
		    $to_delete->{$new_delete} = $to_keep->{$new_delete};
		    $pages_toimp_hash->{$new_delete} = $to_keep->{$new_delete};
		    delete ($to_keep->{$new_delete});
		}
	    }
	}
    }
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
    return if (WikiCommons::is_remote eq "yes");
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
    my $general_categories_hash = $coco->get_categories;
    foreach my $key (sort keys %$general_categories_hash) {
	my $text = "----\n\n";
	$url = "Category:$key";
	if (ref $general_categories_hash->{$key}) {
	    foreach my $sec_key (sort keys %{$general_categories_hash->{$key}} ) {
		$text .= "\[\[Category:$sec_key\]\]\n" if exists $general_categories_hash->{$key}->{$sec_key} ;
#	 	if MIND_Customers add customer info
	    }
	} else {
# 	    $text .= "\[\[Category:$key\]\]\n";
	}
	$text .= "----\n\n";
	if (WikiCommons::is_remote ne "yes"){
	    $our_wiki->wiki_edit_page($url, $text);
	    die "Could not import url $url.\t". (WikiCommons::get_time_diff) ."\n" if ( ! $our_wiki->wiki_exists_page($url) );
	} else {
	    print "\tCopy category to $remote_work_path\n";
	    WikiCommons::makedir("$remote_work_path");
	    WikiCommons::write_file("$remote_work_path/$url", $text);
	}
	my $work_dir = "$wiki_dir/categories/$url";
	WikiCommons::makedir("$work_dir");
	WikiCommons::write_file ("$work_dir/$wiki_files_info", "md5 = 0\nrel_path = 0\nsvn_url = 0\nlink_type = category\n");
	WikiCommons::write_file("$work_dir/$url", $text);

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
	WikiCommons::add_to_remove ("$remote_work_path/$wiki_result", "dir");
	WikiCommons::copy_dir ("$work_dir/$wiki_result", "$remote_work_path/$wiki_result") if -e "$work_dir/$wiki_result";
	copy("$work_dir/$url.full.wiki","$remote_work_path/$url") or die "Copy failed for: $url.full.wiki to $remote_work_path: $!\t". (WikiCommons::get_time_diff) ."\n";
    }

    my $text = "md5 = ".$pages_toimp_hash->{$url}[$md5_pos]."\n";
    $text .= "rel_path = ".$pages_toimp_hash->{$url}[$rel_path_pos]."\n";
    $text .= "svn_url = ".$pages_toimp_hash->{$url}[$svn_url_pos]."\n";
    $text .= "link_type = ".$pages_toimp_hash->{$url}[$link_type_pos]."\n";
    WikiCommons::write_file("$work_dir/$wiki_files_info", $text);
    delete($pages_toimp_hash->{$url});

    my $fail = 0;
    $fail = WikiCommons::cleanup($work_dir);
    opendir(DIR, $work_dir);
    my @files = grep { (!/^\.\.?$/) } readdir(DIR);
    closedir(DIR);
    if (scalar @files > 3 ) {
	print "Dir $work_dir doesn't have the correct number of files.\n";
	$fail = 1;
    }
    foreach my $file (@files){
	if ($file ne $wiki_files_uploaded && $file ne $wiki_files_info && $file !~ m/\.wiki$/ ) {
	    print "File $file from $work_dir should not exist.\n".Dumper(@files);
	    $fail = 1;
	    last ;
	}
    }
    if ($fail){
	my $name_bad = "$bad_dir/$url".time();
	WikiCommons::makedir("$name_bad");
	move("$work_dir","$name_bad");
    }
}

sub work_real {
    my ($to_keep, $path_files) = @_;
    my $total_nr = scalar keys %$pages_toimp_hash;
    my $crt_nr = 0;
    foreach my $url (sort keys %$pages_toimp_hash) {
	$crt_nr++;
	next if ($pages_toimp_hash->{$url}[$link_type_pos] eq "link");
	WikiCommons::reset_time();
	print "\n************************* $crt_nr of $total_nr\nMaking real url for $url\n\t\t$path_files/$pages_toimp_hash->{$url}[$rel_path_pos].\t". (WikiCommons::get_time_diff) ."\n";
	my $svn_url = $pages_toimp_hash->{$url}[$svn_url_pos];
	$svn_url = uri_escape( $svn_url,"^A-Za-z\/:0-9\-\._~%" );
	my $wiki = create_wiki($url, "$path_files/$pages_toimp_hash->{$url}[$rel_path_pos]");
	if (! defined $wiki ){
	    WikiCommons::makedir("$bad_dir/$url");
	    move("$wiki_dir/$url","$bad_dir/$url");
	    delete($pages_toimp_hash->{$url});
	    next;
	}
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
    my $total_nr = scalar keys %$pages_toimp_hash;
    my $crt_nr = 0;

    foreach my $url (sort keys %$pages_toimp_hash) {
	$crt_nr++;
	WikiCommons::reset_time();
	print "\n************************* $crt_nr of $total_nr\nMaking link for url $url\n\t\t$path_files/$pages_toimp_hash->{$url}[$rel_path_pos].\t". (WikiCommons::get_time_diff) ."\n";
	my $link_to = $md5_map->{$pages_toimp_hash->{$url}[$md5_pos]}->{"real"}[0];
	die "We should have a url in to_keep.\n" if (scalar @{$pages_toimp_hash->{$url}} != scalar @{$to_keep->{$link_to}});
	my ($link_name,$link_dir,$link_suffix) = fileparse($to_keep->{$link_to}[$rel_path_pos], qr/\.[^.]*/);
	my ($name,$dir,$suffix) = fileparse($pages_toimp_hash->{$url}[$rel_path_pos], qr/\.[^.]*/);

	my $new_file = "$url$suffix";
	my $link_file = "$wiki_dir/$link_to/$link_to.wiki";
	WikiCommons::makedir("$wiki_dir/$url/");
	WikiCommons::write_file("$wiki_dir/$url/$wiki_files_uploaded", "");
	copy("$link_file","$wiki_dir/$url/$url.wiki") or die "Copy failed for link: $link_file to $wiki_dir/$url: $!\t". (WikiCommons::get_time_diff) ."\n";
	open (FILEHANDLE, "$wiki_dir/$url/$url.wiki") or die $!."\t". (WikiCommons::get_time_diff) ."\n";
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

	if ($path_type eq "users") {
	    my $disabled = $coco->get_disabled_pages();
	    foreach my $key (keys %$disabled){
		delete( $pages_local_hash->{$key});
	    }
	}

	($to_delete, $to_keep) = generate_pages_to_delete_to_import;
    }

# print "$_\n" foreach sort keys %$pages_toimp_hash; exit 1;
    if (WikiCommons::is_remote ne "yes") {
	foreach my $url (sort keys %$to_delete) {
	    print "Deleting $url.\t". (WikiCommons::get_time_diff) ."\n";
	    $our_wiki->wiki_delete_page($url, "$wiki_dir/$url/$wiki_files_uploaded") if ( $our_wiki->wiki_exists_page($url) );
	    remove_tree("$wiki_dir/$url") || die "Can't remove dir $wiki_dir/$url: $?.\n";
	}
    }

#    return ($to_delete, $to_keep);
    return $to_keep;
}

sub work_for_docs {
    my ($path_files) = @_;
    my $to_keep = work_begin;
    make_categories if scalar keys %$pages_toimp_hash;
    work_real($to_keep, $path_files);
    work_link($to_keep);
}

if (-f "$pid_file") {
    open (FH, "<$pid_file") or die "Could not read file $pid_file.\n";
    my @info = <FH>;
    close (FH);
    chomp @info;
    $pid_old = $info[0];
    my $exists = kill 0, $pid_old;
    if ( $exists ) {
	my $proc_name = `ps -p $pid_old -o cmd`;
	print "$proc_name\n";
	die "Process is already running.\n" if $proc_name =~ m/(.+?)generate_wiki\.pl -d (.+?) -n $path_type(.*)/;
    }
}
WikiCommons::write_file($pid_file,"$$\n");

$our_wiki = new WikiWork();
if ($path_type eq "mind_svn") {
    $coco = new WikiMindSVN("$path_files");
    work_for_docs("$path_files");
} elsif ($path_type eq "cms_docs") {
    $coco = new WikiMindCMS("$path_files");
    work_for_docs("$path_files");
} elsif ($path_type eq "users") {
    $coco = new WikiMindUsers("$path_files");
    work_for_docs("$path_files");
} elsif ($path_type eq "crm_docs") {
    $all_real = "yes";
    $coco = new WikiMindCRM("$path_files");

    my $to_keep = work_begin;
# print Dumper($pages_toimp_hash);die;

    my $total_nr = scalar keys %$pages_toimp_hash;
    my $crt_nr = 0;
    foreach my $url (sort keys %$pages_toimp_hash) {
	$crt_nr++;
	WikiCommons::reset_time();
	print "\n************************* $crt_nr of $total_nr\nMaking crm url for $url.\t". (WikiCommons::get_time_diff) ."\n";

	WikiCommons::makedir "$wiki_dir/$url/";
	my $rel_path = "$pages_toimp_hash->{$url}[$rel_path_pos]";

	print "$path_files/$rel_path\n";
	local( $/, *FH ) ;
	open(FH, "$path_files/$rel_path") || die("Could not open file: $!");
	my $wiki_txt = <FH>;
	close (FH);

	WikiCommons::makedir "$wiki_dir/$url/$wiki_result";
	WikiCommons::add_to_remove("$wiki_dir/$url/$wiki_result", "dir");
	my $work_dir = "$wiki_dir/$url";
	WikiCommons::write_file("$work_dir/$url.wiki", $wiki_txt);
	insertdata ($url, $wiki_txt);
    }
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

    $coco = new WikiMindSC("$path_files", WikiCommons::get_urlsep);
    my $to_keep = work_begin;
#     make_categories;
    my $tmp = {};
    foreach (keys %$pages_toimp_hash) {$tmp->{$_} = 1 if ($pages_toimp_hash->{$_}[$link_type_pos] eq "link")};
    die "There are no links.\n" if scalar keys %$tmp;

    my $general_wiki_file = "General_info.wiki";
    my $total_nr = scalar keys %$pages_toimp_hash;
    my $crt_nr = 0;
    foreach my $url (sort keys %$pages_toimp_hash) {
	$crt_nr++;
# next if "$url" !~ "B608142";
	WikiCommons::reset_time();
	print "\n************************* $crt_nr of $total_nr\nMaking sc url for $url.\t". (WikiCommons::get_time_diff) ."\n";

	WikiCommons::makedir "$wiki_dir/$url/";

	if ($url !~ m/^SC:(.*)/i) {
	    my $crt_name = $url;
	    $crt_name =~ s/(SC.*)?:(.*)/$2/i;
	    my $redirect_text = "#REDIRECT [[SC:$crt_name]]";
	    print "\tmake redirect from SC:$crt_name to $url.\n";
	    $our_wiki->wiki_delete_page("$url", "") if $our_wiki->wiki_exists_page("$url");
	    $our_wiki->wiki_move_page("SC:$crt_name", "$url");

	    my $text = "md5 = ".$pages_toimp_hash->{$url}[$md5_pos]."\n";
	    $text .= "rel_path = ".$pages_toimp_hash->{$url}[$rel_path_pos]."\n";
	    $text .= "svn_url = ".$pages_toimp_hash->{$url}[$svn_url_pos]."\n";
	    $text .= "link_type = ".$pages_toimp_hash->{$url}[$link_type_pos]."\n";
	    WikiCommons::write_file("$wiki_dir/$url/$url.wiki", "$redirect_text");
	    WikiCommons::write_file("$wiki_dir/$url/$wiki_files_uploaded", "");
	    WikiCommons::write_file("$wiki_dir/$url/$wiki_files_info", $text);
	    delete($pages_toimp_hash->{$url});
	    next;
	}

	WikiCommons::makedir "$wiki_dir/$url/$wiki_result";
	WikiCommons::add_to_remove ("$wiki_dir/$url/$wiki_result", "dir");
	my $rel_path = "$pages_toimp_hash->{$url}[$rel_path_pos]";
	my $info_crt_h = $pages_toimp_hash->{$url}[$svn_url_pos];

	my $wiki = {};
	local( $/, *FH ) ;
	open(FH, "$path_files/$rel_path/$general_wiki_file") || die("Could not open file: $!");
	my $wiki_txt = <FH>;
	close (FH);
	$wiki_txt =~ s/^[\f ]+|[\f ]+$//mg;

	$wiki_txt .= "\n\n'''FTP links:'''\n\n";
	foreach my $key (keys %$ftp_links) {
	    $wiki_txt .= "[$ftp_links->{$key}/$rel_path $key]\n\n";
	}

	$wiki->{'0'} = $wiki_txt;

	opendir(DIR, "$path_files/$rel_path") || die("Cannot open directory $path_files/$rel_path: $!.\n");
	my @files = grep { (!/^\.\.?$/) && -f "$path_files/$rel_path/$_" && /(\.rtf)|(\.doc)/i } readdir(DIR);
	closedir(DIR);
	my $wrong = "";
	foreach my $file (@files) {
	    my $file = "$path_files/$rel_path/$file";
	    my ($name,$dir,$suffix) = fileparse($file, qr/\.[^.]*/);
	    my ($node, $title, $header) = "";
	    if ($suffix eq ".doc") {
		foreach my $key (keys %$info_crt_h) {
		    next if $key eq "SC_info";
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
	    if (! defined $wiki_txt ){
		$to_keep->{$url} = $pages_toimp_hash->{$url};
		delete($pages_toimp_hash->{$url});
		$wrong = "yes";
		print "Skip url $url\n";
		last;
	    }
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
	    if (! defined $title) {
		print "No title for $name.\n";
		$wrong = "yes";
		last;
	    }
	    $wiki_txt = "\n=$title=\n\n".$header.$wiki_txt."\n\n";
	    $wiki->{$node} = $wiki_txt;

	    ### from dir $url/$doc$type/$wiki_result get all files in $url/$wiki_result
	    WikiCommons::add_to_remove("$wiki_dir/$url/$wiki_result", "dir");
	    WikiCommons::copy_dir ("$wiki_dir/$url/$url $name/$wiki_result", "$wiki_dir/$url/$wiki_result") if ($suffix eq ".doc");
	}
	if ($wrong eq "yes" ){
	    remove_tree("$path_files/$rel_path") || die "Can't remove dir $path_files/$rel_path: $?.\n";
	    next ;
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


sub quick_and_dirty_html_to_wiki {
    my $url = "Installing SSL certificate";
    my $work_dir = "$wiki_dir/$url";
    $wiki_result = "result";
    my $dest = "$work_dir/$wiki_result";
    WikiCommons::makedir ("$dest");
    `cp -R "./installing ssl certificate_files/"* "$work_dir"`;
    my $html_file = "$work_dir/installing ssl certificate.htm";

    my ($name,$dir,$suffix) = fileparse($html_file, qr/\.[^.]*/);
    my $zip_name = $name;
    my ($wiki, $image_files) = WikiClean::make_wiki_from_html ( $html_file );
    return undef if (! defined $wiki );


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
    WikiCommons::add_to_remove( $html_file, "file" );

    insertdata($url, $wiki);
    die "Failed in cleanup.\n" if WikiCommons::cleanup($work_dir);
}


print "End.\n";
unlink("$pid_file") or die "Could not delete the file $pid_file: ".$!."\n";
