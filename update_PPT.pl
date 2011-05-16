#!/usr/bin/perl

use warnings;
use strict;

$SIG{__WARN__} = sub { die @_ };

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

use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."our_perl_lib/lib";

use File::Find;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use File::Copy;
use Encode;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Mind_work::WikiCommons;

our $from_path = shift;
our $to_path = shift;
WikiCommons::makedir ("$to_path") if ! -d "$to_path";
WikiCommons::makedir ("$from_path") if ! -d "$from_path";
my $path_prefix = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";

die "We need the source and destination paths. We got :$from_path and $to_path.\n" if ( ! defined $to_path || ! defined $from_path);
$to_path = abs_path("$to_path");
$from_path = abs_path("$from_path");
my $hash_new = {};
my $hash_prev = {};

sub add_document_local {
    my $doc_file = shift;
    $doc_file = abs_path($doc_file);
    my ($name, $dir, $suffix) = fileparse($doc_file, qr/\.[^.]*/);
    if ( ! -s "$doc_file" || ! -f "$dir/$name.log" ) {
      print "\tEmpty file $doc_file.\n";
      unlink("$doc_file")|| die "can't delete file.\n";
      return;
    }
    open FILE, "$dir/$name.log" or die $!;
    my @info = <FILE>;
    close FILE;
    die "cocot" if @info > 1;
    my @q = split(/\s+/, $info[0], 2);
    if (! (defined $hash_new->{$q[0]} && $hash_new->{$q[0]} eq $q[1])) {
      print "\tFile should not exist: $doc_file.\n";
      unlink("$doc_file");
      unlink "$dir/$name.log";
      return ;
    }
    $hash_prev->{$q[0]} = "$doc_file";
}

sub add_document_ftp {
    my $doc_file = shift;
    $doc_file = abs_path($doc_file);
    return if ! -s "$doc_file";
    $hash_new->{WikiCommons::get_file_md5( $doc_file )} = "$doc_file";
}

sub transform_to {
  my ($file,$type) = @_;
  eval {
      local $SIG{ALRM} = sub { die "alarm\n" };
      alarm 46800; # 13 hours
      system("python", "$path_prefix/unoconv", "-f", "$type", "$file") == 0 or die "unoconv failed: $?";
      alarm 0;
  };
  if ($@) {
      print "Error: Timed out.\n";
      return "error";
  } else {
      print "\tFinished.\n";
      return "ok";
  }
}

sub clean_ftp_dir {
  my $list = shift;
  my ($name,$dir,$suffix) = fileparse($list, qr/\.[^.]*/);

  opendir(DIR, "$dir") || die("Cannot open directory $dir.\n");
  my @files_in_dir = grep { (!/^\.\.?$/) } readdir(DIR);
  closedir(DIR); 
  open FILE, "$list" or die $!;
  my @files_in_listing = <FILE>;
  close FILE;

  foreach my $file (@files_in_dir){
    my $exists = 0;
    foreach my $file_list (@files_in_listing) {
       $exists = 1, last if $file_list =~ m/$file\r?\n?$/gms;
    }
    unlink $file if ! $exists;
  }
}
# "--restrict-file-names=nocontrol", 
system("wget", "-N", "-r", "-l", "inf", "--no-remove-listing", "-P", "$from_path", "ftp://10.10.1.10/SC/", "-A.ppt", "-o", "/var/log/mind/ftp_mirrot.log");
system("find", "$from_path", "-depth", "-type", "d", "-empty", "-exec", "rmdir", "{}", "\;");
system("find", "$to_path", "-depth", "-type", "d", "-empty", "-exec", "rmdir", "{}", "\;");

find ({ wanted => sub { add_document_ftp ($File::Find::name) if -f && (/(\.ppt|\.pptx)$/i) },}, "$from_path" ) if  (-d "$from_path");

find ({ wanted => sub { add_document_local ($File::Find::name) if -f && (/(\.swf)$/i) },}, "$to_path" ) if  (-d "$to_path");

find ({ wanted => sub { clean_ftp_dir ($File::Find::name) if -f && (/^\.listing$/i) },}, "$from_path" ) if  (-d "$from_path");

my @new = (keys %$hash_new);
my @prev = (keys %$hash_prev);
my ($only_new, $only_prev, $common) = WikiCommons::array_diff(\@new, \@prev);
die "ciudat\n" if scalar @$only_prev;
# print Dumper($hash_new, $hash_prev);
# print Dumper($only_new, $only_prev, $common);

foreach (@$only_new){
    my $doc_file = $hash_new->{$_};
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
    my $append = $dir;
    my $q = quotemeta $from_path;
    $append =~ s/^$q//;
    print "$to_path/$append\n";
    WikiCommons::makedir ("$to_path/$append");
    copy($doc_file, "$to_path/$append/$name$suffix") or die "copy failed: $doc_file to $to_path/$append/$name$suffix $!";

    my $res = `ls "$to_path/$append/" | iconv -f UTF-8 -t UTF-8 2> /dev/null`;
    if ($res ne "$name$suffix") {
      # not utf8, presume is hebrew
      $res = `ls "$to_path/$append/" | iconv -f cp1250 -t UTF-8`;
      $res =~ s/\n//gms;
      $res = WikiCommons::normalize_text($res);
      rename("$to_path/$append/$name$suffix", "$to_path/$append/$res");
      ($name,$dir,$suffix) = fileparse("$to_path/$append/$res", qr/\.[^.]*/);
    }
    print "\tGenerating swf file from $name$suffix.\t". (WikiCommons::get_time_diff) ."\n";
    transform_to("$to_path/$append/$name$suffix", 'swf');
    print "\tGenerating pdf file from $name$suffix.\t". (WikiCommons::get_time_diff) ."\n";
    if (transform_to("$to_path/$append/$name$suffix", 'pdf') =~ m/^ok$/i) {
      `pdftotext "$to_path/$append/$name.pdf"`;
      die "Could not create txt file from pdf $to_path/$append/$name.pdf: $?.\n" if ($?) || ! -f "$to_path/$append/$name.txt";
      unlink "$to_path/$append/$name.pdf" || die "Could not unlink $to_path/$append/$name.pdf: $!";
    }

#     unlink "$to_path/$append/$name$suffix" || die "Could not unlink $to_path/$append/$name$suffix: $!";
    WikiCommons::write_file( "$to_path/$append/$name.log", "$_\t$doc_file");
    ## we should check we have now only ppt, swf, log and txt files here
    ## ....
    print "\tDone for $name$suffix.\t". (WikiCommons::get_time_diff) ."\n";
}
