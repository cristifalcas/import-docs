#!/usr/bin/perl

use warnings;
use strict;
$SIG{__WARN__} = sub { die @_ };
$| = 1;

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
use File::Copy;
use File::Path qw(make_path remove_tree);;
use Encode;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

my $path_prefix = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
use Log::Log4perl qw(:easy);
Log::Log4perl->init("$path_prefix/log4perl.config");
sub logfile {
  return "/var/log/mind/wiki_logs/wiki_update_ppt";
} 

my @crt_timeData = localtime(time);
foreach (@crt_timeData) {$_ = "0$_" if($_<10);}
INFO "Start: ". ($crt_timeData[5]+1900) ."-".($crt_timeData[4]+1)."-$crt_timeData[3] $crt_timeData[2]:$crt_timeData[1]:$crt_timeData[0].\n";

use Mind_work::WikiCommons;

our $from_path = shift;
my $to_path="/media/wiki_files/ppt_as_flash/";
WikiCommons::makedir ($to_path) if ! -d $to_path;
WikiCommons::makedir ($from_path) if ! -d $from_path;
$to_path = abs_path($to_path);
$from_path = abs_path($from_path);
WikiCommons::set_real_path($path_prefix);
LOGDIE "We need the source and destination paths. We got :$from_path and $to_path.\n" if ( ! defined $to_path || ! defined $from_path);

my $hash_ftp = {};
my $hash_swf = {};

sub add_document_local {
    my $doc_file = shift;

    if ($doc_file !~ m/\.(swf|txt|pptx?)$/i) {
      ERROR "\tStrange file $doc_file.\n";
      unlink $doc_file || LOGDIE "can't delete file.\n";
      return;
    }
    $doc_file = abs_path($doc_file);
    my ($name, $dir, $suffix) = fileparse($doc_file, qr/\.[^.]*/);
    if ($doc_file =~ m/^\Q$to_path\E\/([a-z][0-9]+)\/\Q$name$suffix\E$/i) {
	my $sc_id = $1;
	my $q = "";
	$q = "_".(-s $doc_file) if $suffix =~ m/^\.pptx?$/i;
	$hash_swf->{$sc_id}->{"$name$q".lc($suffix)} = $doc_file;
    } else {
	return if $doc_file =~ m/^\/media\/wiki_files\/ppt_as_flash\/__presentations\//
		    || $doc_file =~ m/^\/media\/wiki_files\/ppt_as_flash\/users_imports\//;
	LOGDIE "\tFile $doc_file is not in the correct dir:\n".Dumper($to_path, $name, $suffix);
# 	unlink $doc_file || LOGDIE "can't delete file.\n";
# 	return;
    }
}

sub add_document_ftp {
    my $doc_file = shift;
    $doc_file = abs_path($doc_file);
    LOGDIE "Strange file here: $doc_file.\n"  if $doc_file !~ m/(\.ppt|\.pptx)$/i && $doc_file !~ m/\/.listing$/i;
    my $cleaned_doc_file = clean_file_name($doc_file);
    my ($name, $dir, $suffix) = fileparse($cleaned_doc_file, qr/\.[^.]*/);
    if ($doc_file =~ m/^(.*?)(Def|Market|Test)Attach\/([A-Z][0-9]+)\/(.*)$/i) {
	if ($doc_file =~ m/\/.listing$/i) {
	    unlink $doc_file;
	    return;
	}
	my $size = -s $doc_file;
# LOGDIE Dumper($doc_file,$name,$size,$suffix) if ! defined $3;
	$hash_ftp->{$3}->{"$name\_$size".lc($suffix)} = $doc_file;
    } else {
	LOGDIE "What to do with you, doc file $doc_file\n";
    }
}

sub clean_file_name {
    my $doc_file = shift;
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
    my $res = `cd "$dir" && ls "$name$suffix" | iconv -f cp1250 -t UTF-8 2> /dev/null`;
    $res =~ s/\n//gms;
    $res =~ s/(^\s*)|(\s*$)//sgm;
    $res =~ s/\s+/ /sgm;
    $res = WikiCommons::normalize_text($res);
    return "$dir$res";
}

sub get_work {
    foreach my $ftp_sc_id (sort keys %$hash_ftp) {
	if (defined $hash_swf->{$ftp_sc_id}) {
	    my $all_files = $hash_ftp->{$ftp_sc_id};
	    foreach my $file (keys %$all_files) {
# print Dumper($hash_ftp->{$ftp_sc_id}, $hash_swf->{$ftp_sc_id}, $file) if $file =~ m/B27354 - Amend the Tibco protocol on the RTS/i;
		if (defined $hash_swf->{$ftp_sc_id}->{$file}) {
# print Dumper($hash_ftp->{$ftp_sc_id}, $hash_swf->{$ftp_sc_id}, $file) if $file =~ m/B27354 - Amend the Tibco protocol on the RTS/i;
		    my $file_path = abs_path($hash_swf->{$ftp_sc_id}->{$file});
		    my ($name, $dir, $suffix) = fileparse($file_path, qr/\.[^.]*/);
		    if (defined $hash_swf->{$ftp_sc_id}->{"$name.txt"} && -s "$dir$name.txt" 
			    && defined $hash_swf->{$ftp_sc_id}->{"$name.swf"} && -s "$dir$name.swf") {
			INFO "File is already done: $file_path.\n";
			delete $hash_swf->{$ftp_sc_id}->{"$name.txt"};
			delete $hash_swf->{$ftp_sc_id}->{"$name.swf"};
			delete $hash_swf->{$ftp_sc_id}->{$file};
			delete $hash_ftp->{$ftp_sc_id}->{$file};
		    } else {
			ERROR "Files $file_path not ok:\n".Dumper("$dir$name.txt = ",(-s "$dir$name.txt"),"$dir$name.swf = ",(-s "$dir$name.swf"));
			last;
		    }
		} else {
		}
	    }
	}
	delete $hash_ftp->{$ftp_sc_id} if defined $hash_swf->{$ftp_sc_id} && ! scalar keys %{$hash_swf->{$ftp_sc_id}};
    }
    foreach (sort keys %$hash_swf){
	my $q = $hash_swf->{$_};
	foreach (sort keys %$q){
	    ERROR "Delete file $q->{$_}\n";
	    unlink $q->{$_} || LOGDIE "can't delete \n";
	}
    }
}

my $count=0;
sub clean_ftp_dir {
  my $list = shift;
  INFO "\tDone $count.\r" if (++$count % 100 == 0);
  my ($name,$dir,$suffix) = fileparse($list, qr/\.[^.]*/);

  opendir(DIR, $dir) || LOGDIE ("Cannot open directory $dir.\n");
  my @files_in_dir = grep { (!/^\.\.?$/) } readdir(DIR);
  closedir(DIR);
  open FILE, $list or LOGDIE $!;
  my @files_in_listing = <FILE>;
  close FILE;
  my $files_in_listing_str = join "", @files_in_listing;
  $files_in_listing_str =~ s/\r//mg;
  foreach my $file (@files_in_dir){
    next if -d "$dir/$file" || $file eq ".listing";
    if ($files_in_listing_str =~ m/\Q$file\E$/m && $file =~ m/\.pptx?$/i) {
    } else {
	ERROR Dumper("file does NOT exists $dir/$file.\n$files_in_listing_str");
	unlink $file || LOGDIE "can't delete file $dir/$file.\n";
    }
  }
  unlink $list || LOGDIE "can't delete list $list.\n";
}

LOGDIE "Paths are not correct: \n\t$from_path\n\t$to_path"  if ! (-d $from_path && -d $to_path);
#   system("wget", "-N", "-r", "-l", "inf", "--no-remove-listing", "-P", "$from_path", "ftp://10.10.1.10/SC/", "-A.ppt,PPT,PPt,PpT,pPT,Ppt,pPt,ppT", "-o", "/var/log/mind/wiki_logs/wiki_ftp_mirror.log");
INFO "Clean ftp dir.\n";
find ({ wanted => sub { clean_ftp_dir ($File::Find::name) if -f && (/^\.listing$/i) },}, $from_path );
INFO "Get all ppt files.\n";
# find ({ wanted => sub { add_document_ftp ($File::Find::name) if -f && (/(\.pptx?)$/i) },}, $from_path ) if  (-d $from_path);
find ({ wanted => sub { add_document_ftp ($File::Find::name) if -f },}, $from_path );
INFO "Get all swf files.\n";
# find ({ wanted => sub { add_document_local ($File::Find::name) if -f && (/(\.swf)$/i) },}, $to_path ) if  (-d $to_path);
find ({ wanted => sub { add_document_local ($File::Find::name) if -f },}, $to_path );
INFO "Cleaning $from_path dir ...\n";
system("find", "$from_path", "-depth", "-type", "d", "-empty", "-exec", "rmdir", "{}", "\;");
INFO "Cleaning $to_path dir ...\n";
system("find", "$to_path", "-depth", "-type", "d", "-empty", "-exec", "rmdir", "{}", "\;");
INFO "Done cleaning.\n";

get_work();
my ($crt, $total) = (0,0);
foreach (keys %$hash_ftp){foreach (keys %{$hash_ftp->{$_}}){$total++;}}

foreach my $ftp_sc_id (sort keys %$hash_ftp) {
    my $names = $hash_ftp->{$ftp_sc_id};
    foreach my $file_name (sort keys %$names) {
# print Dumper($hash_ftp->{$ftp_sc_id}, $hash_swf->{$ftp_sc_id}, $file_name) if $file_name =~ m/B27354 - Amend the Tibco protocol on the RTS/i;
# next if $file_name !~ m/B27354 - Amend the Tibco protocol on the RTS/i;
	$crt++;
	INFO "\tStart working for $file_name ($crt out of $total).\n";
	make_path ("$to_path/$ftp_sc_id");
	my $doc_file = $names->{$file_name};
	my ($name_1,$dir_1,$suffix_1) = fileparse($doc_file, qr/\.[^.]*/);
	my ($name_2,$dir_2,$suffix_2) = fileparse($file_name, qr/\.[^.]*/);
	LOGDIE "coco\n".Dumper($suffix_1, $suffix_2) if lc($suffix_1) ne $suffix_2;
	my $clean_file_name = "$name_2$suffix_2";
	$clean_file_name =~ s/^(.*?)(_[0-9]+)($suffix_2)$/$1$3/;
	LOGDIE Dumper($clean_file_name, "$name_2$suffix_2", $suffix_1) if $clean_file_name eq "$name_2$suffix_2";
	my ($name,$dir,$suffix) = fileparse($clean_file_name, qr/\.[^.]*/);
	copy($doc_file, "$to_path/$ftp_sc_id/$clean_file_name");
	WikiCommons::generate_html_file("$to_path/$ftp_sc_id/$clean_file_name", 'swf');
	next if ! -s "$to_path/$ftp_sc_id/$name.swf";
	WikiCommons::generate_html_file("$to_path/$ftp_sc_id/$clean_file_name", 'pdf');
	next if ! -s "$to_path/$ftp_sc_id/$name.pdf";
	`pdftotext "$to_path/$ftp_sc_id/$name.pdf"`;
	next if ($?) || ! -s "$to_path/$ftp_sc_id/$name.txt" || ! -s "$to_path/$ftp_sc_id/$name.pdf" || ! -s "$to_path/$ftp_sc_id/$name.swf";
	unlink "$to_path/$ftp_sc_id/$name.pdf";
	delete $hash_ftp->{$ftp_sc_id}->{$file_name};
	INFO "\tDone for $file_name.\n";
    }
}

INFO "Failed files:\n".Dumper($hash_ftp);
