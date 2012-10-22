#!/usr/bin/perl -w
use warnings;
use strict;
$| = 1;

# select q.*,w.*,e.* from wikidb.page q, wikidb.text w, wikidb.revision e
# where page_namespace>=100 and page_namespace<200
# and e.rev_timestamp>'20121004000000' and e.rev_timestamp<'20121015000000' 
# and e.rev_text_id =w.old_id
# and q.page_latest=e.rev_id LIMIT 0, 300

use Cwd 'abs_path';
use File::Basename;
# use File::Copy;
# use File::Find;
# use Getopt::Std;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;

my $q = `id -u wiki_2`;
my $w = `id -u wiki_3`;
chomp($q); chomp($w);
print Dumper($q,$w );
exit 1;

my $path_prefix = (fileparse(abs_path($0), qr/\.[^.]*/))[1]."";
print "$path_prefix\n";
# my $real_path = abs_path($0);
use lib (fileparse(abs_path($0), qr/\.[^.]*/))[1]."our_perl_lib/lib";

use Email::Outlook::Message;

  my $msg = new Email::Outlook::Message "q.msg", 0;
  my $mime = $msg->to_email_mime;
# print Dumper(keys %$mime);
# my $h1=$mime->{parts};
# foreach my $vasl (@$h1) {
# my @a1 = @$h1;
# $decoded = decode_base64($encoded);
# shift @a1;
# my @q = split m/--1346421571\.DD8eb1E1\.18865/, $mime->{body_raw};
  print Dumper($mime->{body_raw});
# }