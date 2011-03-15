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
    foreach my $url (@$array) {
      print "rm redir page $url\n";
      $our_wiki->wiki_delete_page($url) if ( $our_wiki->wiki_exists_page("$url") && ! $view_only);
    }
  }

  $hash = $namespaces->{'real'};
  foreach my $ns (keys %$hash){
    $array = $our_wiki->wiki_get_redirects("$hash->{$ns}");
    foreach my $url (@$array) {
      print "rm real page $url\n";
      $our_wiki->wiki_delete_page($url) if ( $our_wiki->wiki_exists_page("$url") && ! $view_only);
    }
  }

}

sub unused_categories {
    my $all_categories = $our_wiki->wiki_get_categories();
    foreach my $cat (@$all_categories) {
	my $res = $our_wiki->wiki_get_pages_in_category($cat, 1);
	next if defined $res;
	print "rm page $cat\n";
	$our_wiki->wiki_delete_page($cat) if ( $our_wiki->wiki_exists_page("$cat") && ! $view_only);
    }
}

sub wanted_categories {
  my $link = "http://localhost/wiki/index.php?title=Special:WantedCategories&limit=2000&offset=0";
  my $res = get_results($link);
  foreach my $elem (@$res){
      $elem =~ s/ \(page does not exist\)$//;
      my $cat = "Category:$elem";
      print "add category $cat.\n";
      $our_wiki->wiki_edit_page("$cat", "----") if ! $view_only;
  }
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
      if (! $our_wiki->wiki_exists_page("$elem")) {
	print "add page \n\t$elem.\n";
	$our_wiki->wiki_edit_page("$elem", "----") if ( ! $view_only);
      }
      $our_wiki->wiki_delete_page("$elem") if ( ! $view_only);
  }
}

sub fix_wanted_pages {
  my $link = "http://localhost/wiki/index.php?title=Special:WantedPages&limit=2000&offset=0";
  my $res = get_results($link);
  foreach my $elem (@$res){
      next if $elem eq "Special:WhatLinksHere";
      $elem =~ s/ \(page does not exist\)$//;
      print "$elem\n";#
  }
}

sub fix_missing_files {
    ## this will delete pages if the user forgot to add an image
  my $link = "http://localhost/wiki/index.php?title=Special:WantedFiles&limit=2000&offset=0";
  my $res = get_results($link);
  my $missing = {};
  foreach my $elem (@$res){
    my $arr = $our_wiki->wiki_get_pages_using("$elem");
    foreach my $file (@$arr) {
      print "rm page $file\n";
      $our_wiki->wiki_delete_page($file) if ( $our_wiki->wiki_exists_page("$file") && ! $view_only);
    }
  }

}

sub getlocalpages {
  my $namespaces = shift;

  my $local_pages = {};
  opendir(DIR, "$workdir") || die("Cannot open directory $workdir: $!.\n");
  my @alldirs = grep { (!/^\.\.?$/) && m/workfor/ && -d "$workdir/$_" } readdir(DIR);
  closedir(DIR);

  my @allfiles = ();
  foreach my $adir (@alldirs) {
    opendir(DIR, "$workdir/$adir") || die("Cannot open directory $adir: $!.\n");
    print "Get local files from $adir: ";
    my $count = 0;
    foreach my $file (grep { (!/^\.\.?$/) && -d "$workdir/$adir/$_" } readdir(DIR)) {
      $count++;
      my $ns = "";
      if ( $file =~ m/^(.*?):(.*)$/ ) {
        $ns = $1;
	$ns =~ s/ /_/g;
        $file = $2;
        $file = WikiCommons::capitalize_string($file, 'onlyfirst');
	$file = "$ns:$file";
      }
      my $normalyze_file = $file;
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
    print "$tmp\n";
    print "only in local: ".Dumper($only_in1); print "only in wiki: ".Dumper($only_in2);

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


print "##### Fix wiki sc type:\n";
my $namespaces = $our_wiki->wiki_get_namespaces;
$namespaces = fixnamespaces($namespaces);
# print Dumper($namespaces);
fix_wiki_sc_type($namespaces);
print "##### Remove unused categories:\n";
unused_categories;
print "##### Add missing categories:\n";
wanted_categories;
print "##### Fix broken redirects:\n";
broken_redirects;
print "##### Fix double redirects:\n";
scdoubleredirects;
# print "##### Fix missing files:\n";
# fix_missing_files();
print "##### Remove unused images:\n";
unused_images_dirty;
print "##### Wanted pages:\n";
fix_wanted_pages;
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
