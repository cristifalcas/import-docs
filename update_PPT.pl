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
my @failed = ();

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
#     print $q[1]."\n$doc_file\n" if $doc_file ne $q[1];
    $hash_prev->{$q[0]} = $q[1];
}

sub add_document_ftp {
    my $doc_file = shift;
    $doc_file = abs_path($doc_file);
    return if ! -s "$doc_file";
    $hash_new->{WikiCommons::get_file_md5( $doc_file )} = "$doc_file";
}

sub transform_to {
  my ($file,$type) = @_;
  my ($name,$dir,$suffix) = fileparse($file, qr/\.[^.]*/);
  my $output = "";
  eval {
      local $SIG{ALRM} = sub { die "alarm\n" };
      alarm 46800; # 13 hours
      $output = system("python", "$path_prefix/convertors/unoconv", "-f", "$type", "$file") == 0 or die "unoconv failed: $?";
      alarm 0;
  };
  my $status = $@;
  
  if ($status) {
	print "Error: Timed out: $status.\n";
	eval {
	    local $SIG{ALRM} = sub { die "alarm\n" };
	    alarm 46800; # 13 hours
	    my $convert_string = "";
	    if ($type eq "pdf") {
		$convert_string = "pdf:impress_pdf_Export";
	    } elsif ($type eq "swf") {
		$convert_string = "swf:impress_flash_Export";
	    } else {
		die "Unknow type: $type.\n";
	    }
	    system("Xvfb :10235 -screen 0 1024x768x16 &> /dev/null &");
	    system("libreoffice", "-display", ":10235", "-unnaccept=all", "-invisible", "-nocrashreport", "-nodefault", "-nologo", "-nofirststartwizard", "-norestore", "-convert-to", "$convert_string", "-outdir", "$dir", "$file") == 0 or die "libreoffice failed: $?";
	    alarm 0;
	};
	$status = $@;
	if ($status) {
	    print "Error: Timed out: $status.\n";
	} else {
	    print "\tFinished: $status.\n";
	} 
  } else {
      print "\tFinished: $output.\n";
      return 1;
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
# system("wget", "-N", "-r", "-l", "inf", "--no-remove-listing", "-P", "$from_path", "ftp://10.10.1.10/SC/", "-A.ppt,PPT,PPt,PpT,pPT,Ppt,pPt,ppT", "-o", "/var/log/mind/ftp_mirrot.log");
# find ({ wanted => sub { clean_ftp_dir ($File::Find::name) if -f && (/^\.listing$/i) },}, "$from_path" ) if  (-d "$from_path");
# system("find", "$from_path", "-depth", "-type", "d", "-empty", "-exec", "rmdir", "{}", "\;");
# system("find", "$to_path", "-depth", "-type", "d", "-empty", "-exec", "rmdir", "{}", "\;");

find ({ wanted => sub { add_document_ftp ($File::Find::name) if -f && (/(\.ppt|\.pptx)$/i) },}, "$from_path" ) if  (-d "$from_path");

find ({ wanted => sub { add_document_local ($File::Find::name) if -f && (/(\.swf)$/i) },}, "$to_path" ) if  (-d "$to_path");

my @new = (keys %$hash_new);
my @prev = (keys %$hash_prev);
my ($only_new, $only_prev, $common) = WikiCommons::array_diff(\@new, \@prev);
die "ciudat\n" if scalar @$only_prev;
# print Dumper($hash_new, $hash_prev);
# print Dumper($only_new, $only_prev, $common);
print "New files to convert:".(scalar @$only_new).".\n";
foreach (@$only_new){
    my $doc_file = $hash_new->{$_};
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
    my $append = $dir;
    my $q = quotemeta $from_path;
    $append =~ s/^$q//;
    WikiCommons::makedir ("$to_path/$append");
    unlink "$to_path/$append/$name$suffix" if -f "$to_path/$append/$name$suffix";
    copy($doc_file, "$to_path/$append/$name$suffix") or die "copy failed: $doc_file to $to_path/$append/$name$suffix $!";

    my $res = `cd "$to_path/$append/" && ls "$name$suffix" | iconv -f UTF-8 -t UTF-8 2> /dev/null`;
    $res =~ s/\n//gms;
    if ($res ne "$name$suffix") {
# print Dumper($res, "$name$suffix");exit 1;
      # not utf8, presume is hebrew. Code should be cp1255, but we can't work with that.
      $res = `ls "$to_path/$append/" | iconv -f cp1250 -t UTF-8`;
      $res =~ s/\n//gms;
      $res = WikiCommons::normalize_text($res);
      unlink "$to_path/$append/$res" if -f "$to_path/$append/$res";
      copy("$to_path/$append/$name$suffix", "$to_path/$append/$res");
      ($name,$dir,$suffix) = fileparse("$to_path/$append/$res", qr/\.[^.]*/);
    }
    print "\tGenerating swf file from $name$suffix.\t". (WikiCommons::get_time_diff) ."\n";
    if (! transform_to("$to_path/$append/$name$suffix", 'swf')) {
      push @failed, "$to_path/$append/$name$suffix";
      next;
    }
    print "\tGenerating pdf file from $name$suffix.\t". (WikiCommons::get_time_diff) ."\n";
    if (transform_to("$to_path/$append/$name$suffix", 'pdf')) {
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

print "Failed files:\n".Dumper(@failed);
