#!/usr/bin/perl -w
print "Start.\n";
use warnings;
use strict;
$SIG{__WARN__} = sub { die @_ };

#syncronize wiki with local fs: for anything in namespaces
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
use URI::Escape; 
use Mind_work::WikiWork;
use Mind_work::WikiCommons;

my $workdir = "/media/share/Documentation/cfalcas/q/import_docs/work/";
my $our_wiki;
$our_wiki = new WikiWork();

sub getnamespaces {
  my $namespaces = {};
  my $ns = 'grep "\$wgExtraNamespaces" /var/www/html/wiki/LocalSettings.php | sed s/^\$wgExtraNamespaces// | sed s/=// | sed s/\]// | sed s/\\\[// | sed s/\"//g | sed s/\;//';
  my @my_res = split "\n", `$ns`;
  foreach my $line (@my_res){
    my @elem = split ' ', $line;
    die "too many: $line\n" if scalar @elem >2;
    if ($elem[1] =~ m/^SC_/) {
      $namespaces->{'sc_real'}->{$elem[1]} = $elem[0];
    } elsif ($elem[1] =~ m/^SC$/) {
      $namespaces->{'sc_redir'}->{$elem[1]} = $elem[0];
    } else {
      $namespaces->{'non_sc'}->{$elem[1]} = $elem[0];
    }
  }

  return $namespaces;
}

sub getwikiscpagestype {
  my $namespaces = shift;
  my $array = ();
  $array = $our_wiki->wiki_get_redirects("$namespaces->{'sc_redir'}");
  $array = $our_wiki->wiki_get_nonredirects("$namespaces->{'sc_redir'}");

  my %hash = map { $_ => 1 } @$array;
  return \%hash;
}

sub scdoubleredirects {
  my $link = "http://localhost/wiki/index.php?title=Special:DoubleRedirects&limit=2000&offset=0";
  my $res = `lynx -dump "$link"`;
  my $elements = {};

  foreach my $elem (split '\n', $res){
    next if $elem !~ m/^\s*[0-9]+\.\s*http:\/\/localhost\/wiki\/index.php\?title=SC/;
    $elem =~ s/^\s*[0-9]+\.\s*http:\/\/localhost\/wiki\/index.php\?title=//;
    $elem =~ s/&redirect=no.*$//;
    $elements->{$elem} = 1;
  }
  return $elements;
}

sub unused_images {
  my $link = "http://localhost/wiki/index.php?title=Special:UnusedFiles&limit=2000&offset=0";
  my $res = `lynx -dump "$link"`;
  my $images = {};
  foreach my $elem (split '\n', $res){
    next if $elem !~ m/^\s*[0-9]+\.\s*http:\/\/localhost\/wiki\/index.php\/File:/;
    $elem =~ s/^\s*[0-9]+\.\s*http:\/\/localhost\/wiki\/index.php\///;
    $images->{$elem} = 1;
  }
  return $images;
}

sub missing_files {
  my $link = "http://localhost/wiki/index.php?title=Special:WantedFiles&limit=2000&offset=0";
  my $res = `lynx -dump "$link"`;
  my $images = {};
  foreach my $elem (split '\n', $res){
    next if $elem !~ m/^\s*[0-9]+\.\s*http:\/\/localhost\/wiki\/index.php\?title=File:/;
    $elem =~ s/^\s*[0-9]+\.\s*http:\/\/localhost\/wiki\/index.php\?title=//;
    $elem =~ s/&action=edit&redlink=1$//;
    $images->{$elem} = 1;
  }
  return $images;
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
      } elsif ( defined $namespaces->{'sc_redir'}->{$ns} ){
	$local_pages->{'sc_redir'}->{$file} = "$adir";
      } elsif ( defined $namespaces->{'sc_real'}->{$ns} ){
	$local_pages->{'sc_real'}->{$file} = "$adir";
      } elsif ( defined $namespaces->{'non_sc'}->{$ns} ){
	$local_pages->{'non_sc'}->{$file} = "$adir";
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
  my ($localnonsc_pages, $localsc_pages, $localsc_redirs) = @_;
  my $missing = missing_files;
  foreach my $q (keys %$missing) {
    my $arr = $our_wiki->wiki_get_pages_using("$q");
    foreach my $file (@$arr) {
      if ( exists $localnonsc_pages->{$file} ) {
	remove_tree("$workdir/$file") || die "Can't remove dir $workdir/$file: $?.\n";
	delete $localnonsc_pages->{$file};
      } elsif ( exists $localsc_pages->{$file} ) {
	remove_tree("$workdir/$file") || die "Can't remove dir $workdir/$file: $?.\n";
	delete $localsc_pages->{$file};
      }
      $our_wiki->wiki_delete_page($file);
    }
  }
}

sub fix_sc_double_redirects {
  my ($localsc_pages,$localsc_redirs) = @_;
  my $doubleredirects = scdoubleredirects;
}

my $namespaces = getnamespaces;
my $local_pages = getlocalpages($namespaces);
my $wiki_pages = getwikipages($namespaces);
#WikiCommons::hash_to_xmlfile( $local_pages, "q_local_pages.xml");
#WikiCommons::hash_to_xmlfile( $wiki_pages, "q_wiki_pages.xml");

my ($hash1, $hash2, @arr1, @arr2, $only_in1, $only_in2, $common);
@arr1 = (sort keys %$local_pages);
@arr2 = (sort keys %$wiki_pages);

## non_sc
$hash1 = $local_pages->{'non_sc'};
$hash2 = $wiki_pages->{'non_sc'};
@arr1 = (sort keys %$hash1);
@arr2 = (sort keys %$hash2);
($only_in1, $only_in2, $common) = WikiCommons::array_diff(\@arr1, \@arr2);
print "non_sc in local ".Dumper($only_in1);
print "non_sc in wiki ".Dumper($only_in2);
## sc_real
$hash1 = $local_pages->{'sc_real'};
$hash2 = $wiki_pages->{'sc_real'};
@arr1 = (sort keys %$hash1);
@arr2 = (sort keys %$hash2);
($only_in1, $only_in2, $common) = WikiCommons::array_diff(\@arr1, \@arr2);
print "sc_real in local ".Dumper($only_in1);
print "sc_real in wiki ".Dumper($only_in2);
## sc_redir
$hash1 = $local_pages->{'sc_redir'};
$hash2 = $wiki_pages->{'sc_redir'};
@arr1 = (sort keys %$hash1);
@arr2 = (sort keys %$hash2);
($only_in1, $only_in2, $common) = WikiCommons::array_diff(\@arr1, \@arr2);
print "sc_redir in local ".Dumper($only_in1);
print "sc_redir in wiki ".Dumper($only_in2);

# my $local_pages = WikiCommons::xmlfile_to_hash( "local_pages.xml");
# print Dumper($local_pages);

# fix_missing_files ($localnonsc_pages, $localsc_pages,$localsc_redirs);
#
# my $wikinonsc_pages = allpagesinwiki();
# my $wikisc_pages = allpagesinwiki("sc");
# my $wikisc_redirs = sconly('r');
# my $wikisc_nonredirs = sconly;
# print Dumper($wikisc_nonredirects);

# $nr = scalar keys %$wiki_pages;
# print "$nr\n";
# $nr = scalar keys %$local_pages;
# print "$nr\n";
# $nr = scalar keys %$wiki_redirs;
# print "$nr\n";
# print Dumper($arr);
# $nr = scalar keys %$local_redirs;
# print "$nr\n";

## in SC namespace we should have only redirects that are also on the filesystem
## only in SC: remove the pages and the redirect
## only on FS: remove the dir from fs


## in SC namespace we should NOT have any pages that are not redirects
## remove the pages and the dirs from fs

## there should not be any double redirects
## remove all from the wiki and also from fs


## remove all unused images from wiki
# my $unusedimages = unused_images;
