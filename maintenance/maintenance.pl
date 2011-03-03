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

use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."../our_perl_lib/lib";
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use File::Path qw(remove_tree);
use Mind_work::WikiWork;
use Mind_work::WikiCommons;

my $workdir = "/media/share/Documentation/cfalcas/q/import_docs/work/";
my $our_wiki;
$our_wiki = new WikiWork();
my ($local_pages, $wiki_pages);
my $view_only = 1;

sub fixnamespaces {
  my $namespaces = shift;
  my $res = {};
  foreach my $ns_nr (keys %$namespaces){
    if ($ns_nr >= 100) {
	my $name = $namespaces->{$ns_nr};
	if ($name =~ m/^(SC |CRM )/) {
	    $res->{'real'}->{$name} = $ns_nr;
	} elsif ($name =~ m/^(SC|CRM)$/) {
	    $res->{'redir'}->{$name} = $ns_nr;
	} else {
	    $res->{'normal'}->{$name} = $ns_nr;
	}
    } else {
	$res->{'wiki_private'}->{$namespaces->{$ns_nr}} = $ns_nr;
    }
  }

  return $res;
}

sub fix_wiki_sc_type {
  my $namespaces = shift;
  my $array = ();
  my $hash = $namespaces->{'redir'};
  foreach my $ns (keys %$hash){
    $array = $our_wiki->wiki_get_nonredirects("$hash->{$ns}");
    foreach my $url (@$array) {
      print "rm page $url\n";
      $our_wiki->wiki_delete_page($url, "") if ( $our_wiki->wiki_exists_page("$url") && ! $view_only);
    }
  }

  $hash = $namespaces->{'real'};
  foreach my $ns (keys %$hash){
    $array = $our_wiki->wiki_get_redirects("$hash->{$ns}");
    foreach my $url (@$array) {
      print "rm page $url\n";
      $our_wiki->wiki_delete_page($url, "") if ( $our_wiki->wiki_exists_page("$url") && ! $view_only);
    }
  }

}

sub unused_categories {
    my $all_categories = $our_wiki->wiki_get_categories();
    foreach my $cat (@$all_categories) {
	my $res = $our_wiki->wiki_get_pages_in_category($cat, 1);
	next if defined $res;
	print "rm page $cat\n";
	$our_wiki->wiki_delete_page($cat, "") if ( $our_wiki->wiki_exists_page("$cat") && ! $view_only);
    }
}

sub wanted_categories {
  my $link = "http://localhost/wiki/index.php?title=Special:WantedCategories&limit=2000&offset=0";
  my $res = `lynx -dump "$link"`;
  
  my $i = 1;
  foreach my $elem (split '\n', $res) {
    $elem =~ s/\x{e2}\x{80}\x{8e}//g;
    next if $elem !~ m/^\s*$i\.\s+\[[0-9]+\](.*)? (\([0-9]+(.*?)members?\))$/;
    my $cat = "Category:$1";
    $i++;
    print "add category $cat.\n";
    $our_wiki->wiki_edit_page("$cat", "----");
  }
}

sub broken_redirects {
  my $link = "http://localhost/wiki/index.php?title=Special:BrokenRedirects&limit=2000&offset=0";
  my $res = `lynx -dump "$link"`;

  foreach my $elem (split '\n', $res){
    next if $elem !~ m/^\s*[0-9]+\.\s*http:\/\/localhost\/wiki\/index.php\?title=SC(.*?)&redirect=no/;
    $elem =~ s/^\s*[0-9]+\.\s*http:\/\/localhost\/wiki\/index.php\?title=//;
    $elem =~ s/&redirect=no$//;
    print "rm page $elem.\n";
    $our_wiki->wiki_delete_page($elem, "") if ( $our_wiki->wiki_exists_page("$elem") );
  }
}

sub scdoubleredirects {
  my $link = "http://localhost/wiki/index.php?title=Special:DoubleRedirects&limit=2000&offset=0";
  my $res = `lynx -dump "$link"`;

  foreach my $elem (split '\n', $res){
    $elem =~ s/\x{e2}\x{80}\x{8e}//g;
    next if $elem !~ m/^\s*[0-9]+\.\s*http:\/\/localhost\/wiki\/index.php\?title=SC/;
    $elem =~ s/^\s*[0-9]+\.\s*http:\/\/localhost\/wiki\/index.php\?title=//;
    $elem =~ s/&redirect=no.*$//;
    print "rm page $elem.\n";
    $our_wiki->wiki_delete_page($elem, "") if ( $our_wiki->wiki_exists_page("$elem") );
  }
}

sub unused_images {
  my $link = "http://localhost/wiki/index.php?title=Special:UnusedFiles&limit=2000&offset=0";
  my $images = 1;

  while ($images) {
    $images = 0;
    my $res = `lynx -dump "$link"`;
    foreach my $elem (split '\n', $res){
      $elem =~ s/\x{e2}\x{80}\x{8e}//g;
      next if $elem !~ m/^\s*[0-9]+\.\s*http:\/\/localhost\/wiki\/index.php\/File:/;
      $images = 1;
      $elem =~ s/^\s*[0-9]+\.\s*http:\/\/localhost\/wiki\/index.php\///;
      print "rm page $elem.\n";
      $our_wiki->wiki_delete_page($elem, "") if ( $our_wiki->wiki_exists_page("$elem") );
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
    foreach my $file (grep { (!/^\.\.?$/) && -d "$workdir/$adir/$_" } readdir(DIR)) {
      my $ns = "";
      if ( $file =~ m/^(.*?):(.*)$/ ) {
        $ns = $1;
        $file = $2;
        $file = WikiCommons::capitalize_string($file, 'onlyfirst');
	$file = "$ns:$file";
      }
      $file =~ s/_/ /g;
      if ($ns eq "") {
	$local_pages->{'gorgonzola'}->{$file} = "$adir";
      } elsif ( defined $namespaces->{'redir'}->{$ns} ){
	$local_pages->{'redir'}->{$file} = "$adir";
      } elsif ( defined $namespaces->{'real'}->{$ns} ){
	$local_pages->{'real'}->{$file} = "$adir";
      } elsif ( defined $namespaces->{'normal'}->{$ns} ){
	$local_pages->{'normal'}->{$file} = "$adir";
      }
    }
    closedir(DIR);
  }

  return $local_pages;
}

sub getwikipages {
  my $namespaces = shift;

  my $wiki_pages = {};
  my @arr = ();
  foreach my $nstype (keys %$namespaces) {
    my $tmp = $namespaces->{$nstype};
    @arr = ();
    foreach my $ns (keys %$tmp) {
      my $def = $our_wiki->wiki_get_all_pages($namespaces->{$nstype}->{$ns});
      foreach (@$def) { if (defined $_) {push @arr, $_} };
    }
    my %hash = map { $_ => 1 } @arr;
    $wiki_pages->{$nstype} = \%hash;
  }
  return $wiki_pages;
}

sub fix_missing_files {
    ## this will delete pages if the user forgot to add an image
  my $link = "http://localhost/wiki/index.php?title=Special:WantedFiles&limit=2000&offset=0";
  my $res = `lynx -dump "$link"`;
  my $missing = {};
  foreach my $elem (split '\n', $res){
    $elem =~ s/\x{e2}\x{80}\x{8e}//g;
    next if $elem !~ m/^\s*[0-9]+\.\s*http:\/\/localhost\/wiki\/index.php\?title=File:/;
    $elem =~ s/^\s*[0-9]+\.\s*http:\/\/localhost\/wiki\/index.php\?title=//;
    $elem =~ s/&action=edit&redlink=1$//;
    $missing->{$elem} = 1;
  }

  foreach my $q (keys %$missing) {
    my $arr = $our_wiki->wiki_get_pages_using("$q");
    foreach my $file (@$arr) {
#       if ( exists $local_pages->{'non_sc'}->{$file} ) {
# 	print "rm dir $workdir/$local_pages->{'non_sc'}->{$file}/$file\n";
# 	remove_tree("$workdir/$local_pages->{'non_sc'}->{$file}/$file") || die "Can't remove dir $workdir/$local_pages->{'non_sc'}->{$file}/$file: $?.\n";
#       } elsif ( exists $local_pages->{'sc_real'}->{$file} ) {
# 	print "rm dir $workdir/$local_pages->{'sc_real'}->{$file}/$file\n";
# 	remove_tree("$workdir/$local_pages->{'sc_real'}->{$file}/$file") || die "Can't remove dir $workdir/$local_pages->{'sc_real'}->{$file}/$file: $?.\n";
#       }
      print "rm page $file\n";
      $our_wiki->wiki_delete_page($file, "") if ( $our_wiki->wiki_exists_page("$file") );
    }
  }
}

sub syncronize_local_wiki {
  for my $tmp ('non_sc', 'sc_real', 'sc_redir'){
    my $hash1 = $local_pages->{$tmp};
    my $hash2 = $wiki_pages->{$tmp};
    my @arr1 = (sort keys %$hash1);
    my @arr2 = (sort keys %$hash2);
    my ($only_in1, $only_in2, $common) = WikiCommons::array_diff( \@arr1, \@arr2 );
    foreach my $local (@$only_in1) {
      print "rm dir $workdir/$local_pages->{$tmp}->{$local}/$local\n";
      remove_tree("$workdir/$local_pages->{$tmp}->{$local}/$local") || die "Can't remove dir $workdir/$local_pages->{$tmp}->{$local}/$local: $?.\n";
      delete $local_pages->{$tmp}->{$local};
    }
    foreach my $wiki (@$only_in2) {
      print "rm page $wiki\n";
      $our_wiki->wiki_delete_page($wiki, "") if ( $our_wiki->wiki_exists_page("$wiki") );
      delete $wiki_pages->{$tmp}->{$wiki};
    }
  }
}

# my $q = $our_wiki->wiki_get_unused_images;
# $our_wiki->wiki_delete_page("/media/share/Documentation/cfalcas/q/import_docs/dumb");
# print Dumper($q);
my $namespaces = $our_wiki->wiki_get_namespaces;
$namespaces = fixnamespaces($namespaces);
print Dumper($namespaces);
my $q = $our_wiki->wiki_get_all_categories();
print Dumper($q);
# $local_pages = getlocalpages($namespaces);
# $wiki_pages = getwikipages($namespaces);
# print Dumper($local_pages);print Dumper($wiki_pages);exit 1;
# print "##### Fix wiki sc type:\n";
# fix_wiki_sc_type($namespaces);
# print "##### Remove unused categories:\n";
# unused_categories;
# print "##### Add missing categories:\n";
# wanted_categories;
# print "##### Fix broken redirects:\n";
# broken_redirects;
# print "##### Fix double redirects:\n";
# scdoubleredirects;
# print "##### Remove unused images:\n";
# # unused_images;
# print "##### Syncronize:\n";
# syncronize_local_wiki;
