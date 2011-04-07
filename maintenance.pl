#!/usr/bin/perl -w
print "Start.\n";
use warnings;
use strict;
$SIG{__WARN__} = sub { die @_ };

#syncronize wiki with local fs: delete all in only one of them
#fix missing files: find pages with missing files, search for the pages on local dirs and remove them from both

use Cwd 'abs_path','chdir';
use File::Basename;

BEGIN {
    my $path_prefix = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
    my $need= "$path_prefix/instantclient_11_2/";
    my $ld= $ENV{LD_LIBRARY_PATH};
    if(  ! $ld  ) {
        $ENV{LD_LIBRARY_PATH}= $need;
    } elsif(  $ld !~ m#(^|:)\Q$need\E(:|$)#  ) {
        $ENV{LD_LIBRARY_PATH} .= ':' . $need;
    } else {
        $need= "";
    }
    if(  $need  ) {
        exec 'env', $^X, $0, @ARGV;
    }
}

use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."./our_perl_lib/lib";
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use File::Path qw(remove_tree);
use Mind_work::WikiWork;
use Mind_work::WikiCommons;
use HTML::TreeBuilder::XPath;
use Encode;

my $workdir = "/media/share/Documentation/cfalcas/q/import_docs/work/";
my $our_wiki;
$our_wiki = new WikiWork();
my ($local_pages, $wiki_pages);
my $view_only = shift;
$view_only = 1 if ! defined $view_only;

sub fixnamespaces {
  my $namespaces = shift;
  my $res = {};
  foreach my $ns_nr (keys %$namespaces){
    if ($ns_nr >= 100) {
	my $name = $namespaces->{$ns_nr};
	$name =~ s/ /_/g;
	if ($name =~ m/^(SC_|CRM_)/) {
	    $res->{'real'}->{$name} = $ns_nr;
	} elsif ($name =~ m/^(SC|CRM)$/) {
	    $res->{'redir'}->{$name} = $ns_nr;
	} else {
	    $res->{'normal'}->{$name} = $ns_nr;
	}
    } else {
	$res->{'private'}->{$namespaces->{$ns_nr}} = $ns_nr;
    }
  }

  return $res;
}

sub get_results {
  my ($link, $type) = @_;
  $type = "list" if !defined $type;
  my $regexp = "";
  if ($type eq "list" ){
    $regexp = q{/html/body/div[@id="content"]/div[@id="bodyContent"]/div[@class="mw-spcontent"]/ol/li/a/@title};
  } elsif ($type eq "table" ){
    $regexp = q{/html/body/div[@id="content"]/div[@id="bodyContent"]/div[@class="mw-spcontent"]/table[@class="gallery"]/tr/td/div[@class="gallerybox"]/div[@class="gallerytext"]/a/@title};
  } else {
    die "Unknown type: $type.\n";
  }
  my @res;
  my $file_res = WikiCommons::http_get("$link");
  my $tree= HTML::TreeBuilder::XPath->new;
  $file_res = Encode::decode("utf8", $file_res);
  $tree->parse( "$file_res");
  foreach my $result ($tree->findnodes_as_strings($regexp)) {
        push @res, $result;
  }
  $tree->delete;
  return \@res;
}

sub fix_wiki_sc_type {
  my $namespaces = shift;
  my $array = ();
  my $hash = $namespaces->{'redir'};
  foreach my $ns (keys %$hash){
    $array = $our_wiki->wiki_get_nonredirects("$hash->{$ns}");
    print "Found ". (scalar @$array) . " pages in namespace $ns.\n" if defined $array;
    foreach my $url (@$array) {
      print "rm redir page $url\n";
      $our_wiki->wiki_delete_page($url) if ( ! $view_only && $our_wiki->wiki_exists_page("$url") );
    }
  }

  $hash = $namespaces->{'real'};
  foreach my $ns (keys %$hash){
    $array = $our_wiki->wiki_get_redirects("$hash->{$ns}");
    print "Found ". (scalar @$array) . " pages in namespace $ns.\n" if defined $array;
    foreach my $url (@$array) {
      print "rm real page $url\n";
      $our_wiki->wiki_delete_page($url) if ( ! $view_only && $our_wiki->wiki_exists_page("$url") );
    }
  }

}

sub unused_categories {
    my $all_categories = $our_wiki->wiki_get_categories();
    my $result = ();
    foreach my $cat (@$all_categories) {
	my $res = $our_wiki->wiki_get_pages_in_category($cat, 1);
	next if defined $res;
	push @$result, $cat;
# 	print "rm page $cat\n";
# 	$our_wiki->wiki_delete_page($cat) if ( $our_wiki->wiki_exists_page("$cat") && ! $view_only);
    }
    return $result;
}

sub wanted_categories {
  my $link = "http://localhost/wiki/index.php?title=Special:WantedCategories&limit=2000&offset=0";
  my $res = get_results($link);
  my $result = ();
  foreach my $elem (@$res){
      $elem =~ s/ \(page does not exist\)$//;
      my $cat = "Category:$elem";
      push @$result, $cat;
#       print "add category $cat.\n";
#       $our_wiki->wiki_edit_page("$cat", "----") if ! $view_only;
  }
  return $result;
}

sub broken_redirects {
  my $link = "http://localhost/wiki/index.php?title=Special:BrokenRedirects&limit=2000&offset=0";
  my $res = get_results($link);
  my $seen = {};
  foreach my $elem (@$res){
    next if $seen->{$elem};
    $elem =~ s/ \(page does not exist\)$//;
    $seen->{$elem} = 1;
    print "rm page $elem.\n";
    $our_wiki->wiki_delete_page($elem) if ( $our_wiki->wiki_exists_page("$elem") && ! $view_only);
  }
}

sub scdoubleredirects {
  my $link = "http://localhost/wiki/index.php?title=Special:DoubleRedirects&limit=2000&offset=0";
  my $res = get_results($link);
  my $seen = {};
  foreach my $elem (@$res){
    next if $seen->{$elem};
    $seen->{$elem} = 1;
    print "rm page $elem.\n";
    $our_wiki->wiki_delete_page($elem) if ( $our_wiki->wiki_exists_page("$elem") && ! $view_only);
  }
}

sub unused_images_dirty {
  my $link = "http://localhost/wiki/index.php?title=Special:UnusedFiles&limit=2000&offset=0";
  my $res = get_results($link, "table");
  foreach my $elem (@$res){
      $elem =~ s/%27/'/g;
      $elem =~ s/%26/&/g;
      print "rm file $elem.\n";
#       if (! $our_wiki->wiki_exists_page("$elem")) {
# 	print "add page \n\t$elem.\n";
# 	$our_wiki->wiki_edit_page("$elem", "----") if ( ! $view_only);
#       }
      $our_wiki->wiki_delete_page("$elem") if ( ! $view_only);
  }
}

sub fix_wanted_pages {
  my $link = "http://localhost/wiki/index.php?title=Special:WantedPages&limit=3000&offset=0";
  my $res = get_results($link);
  my ($cat, $sc, $crm, $other) = ();
  foreach my $elem (@$res){
      next if $elem eq "Special:WhatLinksHere";
      $elem =~ s/ \(page does not exist\)$//;
#       $elem =~ s/ /_/g;
#       print "$elem\n";#
      if ($elem =~ m/^SC:[A-Z][0-9]+$/) {
	push @$sc, $elem;
      } elsif ($elem =~ m/^CRM:[A-Z][0-9]+$/) {
	push @$crm, $elem;
      } elsif ($elem =~ m/^Category:/) {
	push @$cat, $elem;
      } else {
	push @$other, $elem;
      }
  }
  return ($cat, $sc, $crm, $other);
}

sub fix_missing_files {
    ## this will delete pages if the user forgot to add an image
  my $link = "http://localhost/wiki/index.php?title=Special:WantedFiles&limit=2000&offset=0";
  my $res = get_results($link);
  my $missing = {};
  foreach my $elem (@$res){
    next if $elem eq "Special:WhatLinksHere";
    $elem =~ s/ \(page does not exist\)//;
    my $arr = $our_wiki->wiki_get_pages_using("$elem");
    foreach my $page (@$arr) {
	print "Get page $page for file $elem.\n";
	$missing->{$page} = 1;
    }
  }
  foreach my $page (keys %$missing) {
      next if $page eq "CMS:MIND-IPhonEX CMS 80.00.020" && $page !~ m/[a-b _]+:/i;
      print "rm page $page.\n";
      $our_wiki->wiki_delete_page($page) if ( $our_wiki->wiki_exists_page("$page") && ! $view_only);
  }
}

sub getlocalpages {
  my $namespaces = shift;

  my $local_pages = {};
  opendir(DIR, "$workdir") || die("Cannot open directory $workdir: $!.\n");
  my @alldirs = grep { (!/^\.\.?$/) && m/workfor/ && -d "$workdir/$_" } readdir(DIR);
  closedir(DIR);

  foreach my $adir (@alldirs) {
    opendir(DIR, "$workdir/$adir") || die("Cannot open directory $adir: $!.\n");
    print "Get local files from $adir: ";
    my $count = 0;
    foreach my $file (grep { (!/^\.\.?$/) && -d "$workdir/$adir/$_" } readdir(DIR)) {
      $count++;
      my $ns = "";
      my $normalyze_file = $file;
      if ( $file =~ m/^(.*?):(.*)$/ ) {
        $ns = $1;
	$normalyze_file = $2;
        $normalyze_file = WikiCommons::capitalize_string( $normalyze_file, 'onlyfirst' );
	$normalyze_file = "$ns:$normalyze_file";
      }
      $normalyze_file =~ s/ /_/g;
      if ($ns eq "") {
	$local_pages->{'private'}->{$normalyze_file} = "$adir/$file";
      } elsif ( defined $namespaces->{'redir'}->{$ns} ){
	$local_pages->{'redir'}->{$normalyze_file} = "$adir/$file";
      } elsif ( defined $namespaces->{'real'}->{$ns} ){
	$local_pages->{'real'}->{$normalyze_file} = "$adir/$file";
      } elsif ( defined $namespaces->{'normal'}->{$ns} ){
	$local_pages->{'normal'}->{$normalyze_file} = "$adir/$file";
      }
    }
    closedir(DIR);
    print "$count\n";
  }
  return $local_pages;
}

sub getlocalimages {
  our $namespaces = shift;
  use File::Find;
  our $local_pages = {};
  print "Get local images.\n";
  our $count = 0;
  sub process_file {
      my ($file, $full_path) = @_;
      $count++;
      $local_pages->{$file} = "$full_path";
#       die if $count >10;
  };

  my $images_dir = "/var/www/html/wiki/images/";
  opendir(DIR, "$images_dir") || die("Cannot open directory $images_dir: $!.\n");
  my @alldirs = grep { (!/^\.\.?$/) && m/^.$/ && -d "$images_dir/$_" } readdir(DIR);
  closedir(DIR);
  foreach my $dir (@alldirs) {
    eval {find ({wanted => sub { process_file ($_,$File::Find::name) if -f $_ },}, "$images_dir/$dir")};
  }

  return $local_pages;
}

sub getdbimages {
  use DBI;
  my $files = {};
  my $db = DBI->connect('DBI:mysql:wikidb', 'wikiuser', '!0wikiuser@9') || die "Could not connect to database: $DBI::errstr";
  my $sql_query="select distinct il_to from imagelinks";
  my $query = $db->prepare($sql_query);
  $query->execute();
  while (my ($file) = $query->fetchrow_array ){
    $files->{"$file"} = 1;
  }
  return $files;
}

sub getwikipages {
  my $namespaces = shift;

  my $wiki_pages = {};
  my @arr = ();
  foreach my $nstype (keys %$namespaces) {
    next if $nstype eq "private";
    print "Get wiki pages from $nstype.\n";
    my $tmp = $namespaces->{$nstype};
    @arr = ();
    foreach my $ns (keys %$tmp) {
      my $def = $our_wiki->wiki_get_all_pages($namespaces->{$nstype}->{$ns});
      foreach my $page (@$def) { 
	if (defined $page) {
	    $page =~ s/ /_/g;
	    push @arr, "$page";
	} 
      };
    }
    my %hash = map { $_ => 1 } @arr;
    $wiki_pages->{$nstype} = \%hash;
  }
  return $wiki_pages;
}

sub syncronize_local_wiki {
    for my $tmp ('redir', 'real', 'normal'){
	my $hash1 = $local_pages->{$tmp};
	my $hash2 = $wiki_pages->{$tmp};
	my @arr1 = (sort keys %$hash1);
	my @arr2 = (sort keys %$hash2);
	my ($only_in1, $only_in2, $common) = WikiCommons::array_diff( \@arr1, \@arr2 );
	print "$tmp only in local: ".Dumper($only_in1); print "$tmp only in wiki: ".Dumper($only_in2);
	die "Too many to delete.\n" if scalar @$only_in1 > 200 || scalar @$only_in2 > 200;
	foreach my $local (@$only_in1) {
	    print "rm dir $workdir/$local_pages->{$tmp}->{$local}\n";
	    if ( ! $view_only ) {
		remove_tree("$workdir/$local_pages->{$tmp}->{$local}") || die "Can't remove dir $workdir/$local_pages->{$tmp}->{$local}: $?.\n";
	    }
	    delete $local_pages->{$tmp}->{$local};
	}
	foreach my $wiki (@$only_in2) {
	    print "rm page $wiki\n";
	    $our_wiki->wiki_delete_page($wiki) if ( $our_wiki->wiki_exists_page("$wiki") && ! $view_only);
	    delete $wiki_pages->{$tmp}->{$wiki};
	}
    }
}

sub fix_images {
  my $namespaces = shift;

  my $wiki_images = $our_wiki->wiki_get_all_images();
  my $local_images = getlocalimages($namespaces);
  my @local_images = keys %$local_images;
#   my $db_images = getdbimages;
#   my @db_images = keys %$db_images;

#   my ($only_in1, $only_in2, $common) = WikiCommons::array_diff( \@db_images, $wiki_images);
#   ## Files are not imported for those, but are used (missing files):
#   print Dumper($only_in1);
#   ## Nobody links here (unused files):
#   print Dumper($only_in2);

  my ($only_in_wiki, $only_in_fs, $common_all) = WikiCommons::array_diff( $wiki_images, \@local_images);
  ## Files are missing from the fs
  print Dumper($only_in_wiki);
  ## Files found here are not used
  print Dumper($only_in_fs);
}

if ( -f "new 1.txt" ) {
    open(DAT, "new 1.txt") || die("Could not open file!");
    my @raw_data=<DAT>;
    chomp @raw_data;
    close(DAT);
    foreach my $w (@raw_data) {
	my $q = $our_wiki->wiki_get_pages_linking_to("$w");
	print "$w\n";
# 	print Dumper($q);next;
	foreach my $e (@$q){
	    $our_wiki->wiki_delete_page($e);
	}
    }
}

my $namespaces = $our_wiki->wiki_get_namespaces;
$namespaces = fixnamespaces($namespaces);

# # print Dumper($namespaces);
print "##### Fix wiki sc type:\n";
fix_wiki_sc_type($namespaces);
print "##### Fix broken redirects:\n";
broken_redirects;
print "##### Fix double redirects:\n";
scdoubleredirects;
print "##### Fix missing files:\n";
fix_missing_files();
print "##### Remove unused images:\n";
unused_images_dirty;
# print "##### Wanted pages:\n";
# my ($cat, $sc, $crm, $other) = fix_wanted_pages();
# print "##### Get unused categories:\n";
# my $unused = unused_categories();
# print "##### Get missing categories:\n";
# my $wanted = wanted_categories();
print "##### Syncronize wiki files with fs files.\n";
# fix_images($namespaces);
print "##### Syncronize:\n";
$local_pages = getlocalpages($namespaces);
$wiki_pages = getwikipages($namespaces);
syncronize_local_wiki;

# compressOld.php

## all files deleted deleteArchivedFiles.php
# rm -rf /media/share/wiki_images/deleted/*
# delete from filearchive;
## all files overwriten
# rm -rf /media/share/wiki_images/archive/*
# oldimage by oi_timestamp

## all pages deleted: deleteArchivedRevisions.php
# archive ar_namespace, ar_title
## holds the wikitext of individual page revisions: PurgeOldText.php
# text
## holds metadata for every edit done to a page
# revision

# my $q = $our_wiki->wiki_get_all_categories(14);
# print Dumper($q);
