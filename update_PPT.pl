#!/usr/bin/perl

use warnings;
use strict;

$SIG{__WARN__} = sub { die @_ };
$| = 1;

my @crt_timeData = localtime(time);
foreach (@crt_timeData) {$_ = "0$_" if($_<10);}
print "Start: ". ($crt_timeData[5]+1900) ."-".($crt_timeData[4]+1)."-$crt_timeData[3] $crt_timeData[2]:$crt_timeData[1]:$crt_timeData[0].\n";

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
our $work_type = shift;
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
    my $md5sum = WikiCommons::get_file_md5($doc_file);
    $md5sum.=$md5sum while (defined $hash_new->{$md5sum}); ## same file in different paths and too much too change in code
    $hash_new->{$md5sum} = "$doc_file";
}

sub transform_to {
  my ($file,$type) = @_;
  my ($name,$dir,$suffix) = fileparse($file, qr/\.[^.]*/);
  my $output = "";
  eval {
      local $SIG{ALRM} = sub { die "alarm\n" };
      alarm 1800; # 30 minutes
      $output = system("python", "$path_prefix/convertors/unoconv", "-f", "$type", "$file") == 0 or die "unoconv failed: $?";
      alarm 0;
  };
  my $status = $@;
  
  if ($status) {
	print "Error: Timed out: $status.\n";
	`kill -9 \$(ps -ef | egrep soffice.bin\\|oosplash.bin | grep -v grep | gawk '{print \$2}')`;
	eval {
	    local $SIG{ALRM} = sub { die "alarm\n" };
	    alarm 3600; # 1 hour
	    my $convert_string = "";
	    if ($type eq "pdf") {
		$convert_string = "pdf:impress_pdf_Export";
	    } elsif ($type eq "swf") {
		$convert_string = "swf:impress_flash_Export";
	    } else {
		die "Unknow type: $type.\n";
	    }
	    system("Xvfb :10235 -screen 0 1024x768x16 &> /dev/null &");
	    system("libreoffice", "--display", ":10235", "--invisible", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "--convert-to", "$convert_string", "--outdir", "$dir", "$file") == 0 or die "libreoffice failed: $?";
	    alarm 0;
	};
	$status = $@;
	if ($status) {
	    print "Error: Timed out: $status.\n";
	    `kill -9 \$(ps -ef | egrep soffice.bin\\|oosplash.bin | grep -v grep | gawk '{print \$2}')`;
	} else {
	    print "\tFinished: $status.\n";
	    return 1;
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
    if (! $exists){
	print "Removing file $file.\n";
	unlink $file;
    }
  }
}

if ($work_type eq "u") {
  # "--restrict-file-names=nocontrol",
#   print "Updating ftp dir (wget).\n";
#   system("wget", "-N", "-r", "-l", "inf", "--no-remove-listing", "-P", "$from_path", "ftp://10.10.1.10/SC/", "-A.ppt,PPT,PPt,PpT,pPT,Ppt,pPt,ppT", "-o", "/var/log/mind/wiki_logs/wiki_ftp_mirror.log");
  find ({ wanted => sub { clean_ftp_dir ($File::Find::name) if -f && (/^\.listing$/i) },}, "$from_path" ) if  (-d "$from_path");
  print "Cleaning $from_path dir ...\n";
  system("find", "$from_path", "-depth", "-type", "d", "-empty", "-exec", "rmdir", "{}", "\;");
  print "Cleaning $to_path dir ...\n";
  system("find", "$to_path", "-depth", "-type", "d", "-empty", "-exec", "rmdir", "{}", "\;");
  print "Done cleaning.\n";
### cron:
# 0 8 * * * wget -N -r -l inf --no-remove-listing -P /mnt/wiki_files/wiki_files/ftp_mirror/ ftp://10.10.1.10/SC/TestAttach -A.ppt,PPT,PPt,PpT,pPT,Ppt,pPt,ppT -o /var/log/mind/wiki_logs/wiki_ftp_mirror.log &
# 0 8 * * * wget -N -r -l inf --no-remove-listing -P /mnt/wiki_files/wiki_files/ftp_mirror/ ftp://10.10.1.10/SC/DefAttach -A.ppt,PPT,PPt,PpT,pPT,Ppt,pPt,ppT -o /var/log/mind/wiki_logs/wiki_ftp_mirror.log &
# 0 8 * * * wget -N -r -l inf --no-remove-listing -P /mnt/wiki_files/wiki_files/ftp_mirror/ ftp://10.10.1.10/SC/MarketAttach -A.ppt,PPT,PPt,PpT,pPT,Ppt,pPt,ppT -o /var/log/mind/wiki_logs/wiki_ftp_mirror.log &
  exit 0;
}

print "Get all ppt files.\n";
find ({ wanted => sub { add_document_ftp ($File::Find::name) if -f && (/(\.ppt|\.pptx)$/i) },}, "$from_path" ) if  (-d "$from_path");
print "Get all swf files.\n";
find ({ wanted => sub { add_document_local ($File::Find::name) if -f && (/(\.swf)$/i) },}, "$to_path" ) if  (-d "$to_path");

my @new = (keys %$hash_new);
my @prev = (keys %$hash_prev);
my ($only_new, $only_prev, $common) = WikiCommons::array_diff(\@new, \@prev);
die "ciudat\n" if scalar @$only_prev;
print Dumper($only_prev);
# print Dumper($only_new, $only_prev, $common);
print "New files to convert:".(scalar @$only_new).".\n";
foreach (@$only_new){
    my $doc_file = $hash_new->{$_};
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
    print "### Start working for $name ($dir).\n";
    my $append = $dir;
    my $q = quotemeta $from_path;
    $append =~ s/^$q//;
    WikiCommons::makedir ("$to_path/$append");
    unlink "$to_path/$append/$name.log" or die "can't delete $to_path/$append/$name.log: $!.\n" if -f "$to_path/$append/$name.log";
    unlink "$to_path/$append/$name$suffix" or die "can't delete $to_path/$append/$name$suffix: $!.\n" if -f "$to_path/$append/$name$suffix";
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
    if (! transform_to("$to_path/$append/$name$suffix", 'pdf')) {
      push @failed, "$to_path/$append/$name$suffix";
      next;
    } else {
      `pdftotext "$to_path/$append/$name.pdf"`;
      die "Could not create txt file from pdf $to_path/$append/$name.pdf: $?.\n" if ($?) || ! -f "$to_path/$append/$name.txt";
#       unlink "$to_path/$append/$name.pdf" || die "Could not unlink $to_path/$append/$name.pdf: $!";
    }

    WikiCommons::write_file( "$to_path/$append/$name.log", "$_\t$doc_file");
    ## we should check we have now only ppt, swf, pdf, log and txt files here
    ## ....
    print "\tDone for $name$suffix.\t". (WikiCommons::get_time_diff) ."\n";
}

## unintended consequences: this seems to clean all unfinished jobs: there is no .log file (created only on full success) and we remove this shit
find ({ wanted => sub { add_document_local ($File::Find::name) if -f },}, "$to_path" ) if  (-d "$to_path");
finddepth(sub { rmdir $_ if -d }, $to_path);
finddepth(sub { rmdir $_ if -d }, $from_path);

print "Failed files:\n".Dumper(@failed);
