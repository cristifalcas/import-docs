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
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Mind_work::WikiCommons;

our $from_path = shift;
our $to_path = shift;
my $path_prefix = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";

die "We need the source and destination paths. We got :$from_path and $to_path.\n" if ( ! defined $to_path || ! defined $from_path || ! -d $from_path);
WikiCommons::makedir ("$to_path");
$to_path = abs_path("$to_path");
my $hash_new = {};
my $hash_prev = {};

sub add_document_local {
    my $doc_file = shift;
    $doc_file = abs_path($doc_file);
    my ($name, $dir, $suffix) = fileparse($doc_file, qr/\.[^.]*/);
    if ( ! -s "$doc_file" || ! -f "$dir/$name.txt" ) {
      print "\tEmpty file $doc_file.\n";
      unlink("$doc_file")|| die "can't delete file.\n";
      return;
    }
    open FILE, "$dir/$name.txt" or die $!;
    my @info = <FILE>;
    close FILE;
    die "cocot" if @info > 1;
    my @q = split(/\s+/, $info[0], 2);
    if (! (defined $hash_new->{$q[0]} && $hash_new->{$q[0]} eq $q[1])) {
      print "\tFile should not exist: $doc_file.\n";
      unlink("$doc_file");
      unlink "$dir/$name.txt";
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

system("wget", "-N", "-r", "-P", "$from_path", "ftp://10.10.1.10/SC/", "-A.ppt", "-o", "/var/log/mind/ftp_mirrot.log");
system("find", "$from_path", "-depth", "-type", "d", "-empty", "-exec", "rmdir", "{}", "\;");
system("find", "$to_path", "-depth", "-type", "d", "-empty", "-exec", "rmdir", "{}", "\;");

find ({ wanted => sub { add_document_ftp ($File::Find::name) if -f && (/(\.ppt|\.pptx)$/i) },}, "$from_path" ) if  (-d "$from_path");

find ({ wanted => sub { add_document_local ($File::Find::name) if -f && (/(\.swf)$/i) },}, "$to_path" ) if  (-d "$to_path");

my @new = (keys %$hash_new);
my @prev = (keys %$hash_prev);
my ($only_new, $only_prev, $common) = WikiCommons::array_diff(\@new, \@prev);
die "ciudat\n" if scalar @$only_prev;
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
    print "\t-Generating swf file from $name$suffix.\t". (WikiCommons::get_time_diff) ."\n";
    eval {
	local $SIG{ALRM} = sub { die "alarm\n" };
	alarm 46800; # 13 hours
	my $result = `python $path_prefix/unoconv -f swf "$to_path/$append/$name$suffix"`;
	alarm 0;
    };
    if ($@) {
	print "Error: Timed out.\n";
    } else {
	print "\tFinished.\n";
    }
    unlink "$to_path/$append/$name$suffix" || die "Could not unlink $to_path/$append/$name$suffix: $!";
    WikiCommons::write_file( "$to_path/$append/$name.txt", "$_\t$doc_file");
    print "\t+Generating swf file from $name$suffix.\t". (WikiCommons::get_time_diff) ."\n";
}
