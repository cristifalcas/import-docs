package WikiMindSC;

use warnings;
use strict;

our $pages_toimp_hash = {};

sub new {
    my $class = shift;
    my $self = { path_files => shift , url_sep => shift};
    bless($self, $class);
    return $self;
}

sub get_documents {
    my $self = shift;
    my $path_files = $self->{path_files};
    opendir(DIR, "$path_files") || die("Cannot open directory $path_files.\n");
    my @all = grep { (!/^\.\.?$/) && -d "$path_files/$_" } readdir(DIR);
    closedir(DIR);

    my $general_wiki_file = "General_info.wiki";
    my $files_info_file = "files_info.txt";
    my $total = @all;
    my $count = 0;
    print "-Searching for files in SC dir.\t". (WikiCommons::get_time_diff) ."\n";
    foreach my $node (sort @all) {
	$count++;
	print "\tDone $count from a total of $total.\t". (WikiCommons::get_time_diff) ."\n" if ($count%1000 == 0);
# next if $node ne 'B71488';
	die "Can't find files_info or General wiki.\n" if (! -e "$path_files/$node/$files_info_file" || ! -e "$path_files/$node/$general_wiki_file");

	my @categories = ();
	my $md5 = "$node";
	open(FH, "$path_files/$node/$files_info_file") || die("Could not open file!");
	my @data=<FH>;
	chomp @data;
	close(FH);

	foreach my $line (@data) {
	    my @info = split ';', $line;
	    $md5 .= "$info[2]" if defined $info[2];
	}
	$pages_toimp_hash->{$node} = [$md5, "$node", "", "real", \@categories];
    }
    print "\tDone $count from a total of $total.\t". (WikiCommons::get_time_diff) ."\n" if ($count%500 != 0);
    print "+Searching for files in SC dir.\t". (WikiCommons::get_time_diff) ."\n";
    return $pages_toimp_hash;
}

return 1;
