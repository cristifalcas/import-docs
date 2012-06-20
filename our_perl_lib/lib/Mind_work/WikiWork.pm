package WikiWork;

use warnings;
use strict;

use Mind_work::WikiCommons;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use MediaWiki::API;
use MediaWiki::Bot;
# get_last($page, $user)
# get_history($pagename[,$limit])
# get_namespace_names()
# http://en.wikipedia.org/w/api.php
# http://www.mediawiki.org/wiki/API:Lists/es

our $wiki_site_path = "/var/www/html/wiki/";
# our $wiki_url = "http://10.0.0.99/wiki";
our $wiki_url = "http://10.0.0.99/wiki";
our $wiki_url_path = "/wiki";
# our $wiki_url = "http://localhost:1900/wiki";
our $wiki_user = 'wiki_auto_import';
our $wiki_pass = '!0wiki_auto_import@9';
our $robot_user = 'robotuser';
our $robot_pass = '!0robotuser@9';
our $mw;
our $bmw;
our $edit_token;
our $array = ();
our $hash = ();
my $nr_pages = 0;

sub wiki_on_error {
    print "1. Error code: " . $mw->{error}->{code} . "\n";
    print "2. Error details: " . Dumper($mw->{error}->{details})."\n";
    $mw->{response}->{_request}->{_content}="*** deleted ***";
    print "3. Error response: " . Dumper($mw->{response})."\n";
    print "4. Error stacktrace: " . $mw->{error}->{stacktrace}."\n";
    print "time elapsed"."\t". (WikiCommons::get_time_diff) ."\n";
    die;
}

sub new {
    my $class = shift;
    my $self = { user_type => shift};
    if (WikiCommons::is_remote ne "yes" ) {
	my ($user, $pass) = ($wiki_user, $wiki_pass);
	($user, $pass) = ($robot_user, $robot_pass) if defined $self->{'user_type'} && $self->{'user_type'} eq "robot";
	$mw = MediaWiki::API->new({ api_url => "$wiki_url/api.php" }, retries  => 3) or die "coco";
	$mw->{config}->{on_error} = \&wiki_on_error;
	$mw->login( {lgname => $user, lgpassword => $pass } )
	    || die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    }
    bless($self, $class);
    return $self;
}

sub wiki_get_namespaces {
    my $self = shift;
    my %return;
    my $res = $mw->api({
            action => 'query',
            meta   => 'siteinfo',
            siprop => 'namespaces'
    });

    foreach my $id (keys %{ $res->{query}->{namespaces} }) {
        $return{$id} = $res->{query}->{namespaces}->{$id}->{'*'};
    }
    if  (!($return{1} or $_[0] > 1)) {
        %return = $mw->get_namespace_names($_[0] + 1);
    }
    return \%return;
}

sub delete_archived_image {
    my ($self, $archive) = @_;
    my $summary = 'deleting old version of image';
    my ($timestamp, $file) = split(m/!/, $archive);
    my $res;

    if  ( wiki_exists_page("File:$file") ) {
    $res = $mw->api({
        action   => 'delete',
        title    => "File:$file",
        reason   => $summary,
        oldimage => $archive,
    });
    }
    return $res;
}

sub wiki_get_categories {
    my $self = shift;
    my $res = wiki_get_all_pages($self, 14);
    return $res;
}

sub wiki_get_images {
    my $self = shift;
    my $res = wiki_get_all_pages($self, 6);
    return $res;
}

sub wiki_get_all_categories {
    my $self = shift;
    $array = ();

    $mw->list ( { action => 'query',
	    list => 'allcategories', aclimit=>'5000',},
	{ max => 1000, hook => \&wiki_add_url } )
		|| die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
}

sub wiki_get_all_images {
    my $self = shift;
    $array = ();

    $mw->list ( { action => 'query',
	    list => 'allimages', ailimit=>'5000',},
	{ max => 1000, hook => \&wiki_add_url } )
		|| die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
}

sub wiki_get_page {
  my $self = shift;
  my $page = $mw->get_page( { title => @_ } );
  return $page;
}

sub wiki_get_page_section {
  my ($self, $title, $section) = @_;
  my $page = $mw->get_page( { title => "$title#$section" } );
  return $page;
}

sub wiki_delete_page {
  my ($self, $title) = @_;

    my @img = ();
    if (ref($title) eq "ARRAY") {
      @img = @$title;
    } elsif (ref($title) eq "") {
      ## check if $images is a file or an url
	if (-f "$title") {
	    open(FILE, "$title");
	    @img = <FILE>;
	    close FILE;
	} else {
	  push @img, $title;
	}
    } else {
      die "Unknown type for images: ".Dumper($title);
    }

    foreach my $url (@img) {
      chomp $url;
      my $page = $mw->get_page( { title => $url } );
      unless ( defined $page->{missing} ) {
	print "\tDelete page $url.\n";
	$mw->edit( { action => 'delete', title => $url, reason => 'no longer needed' } )
	|| die "Could not delete url $url: ".$mw->{error}->{code} . ': ' . $mw->{error}->{details}."\t". (WikiCommons::get_time_diff) ."\n";
      }
    }
}

sub wiki_get_deleted_revs {
    my ($self, $ns) = @_;
    $ns = 0 if not defined $ns;
    $array = ();

    $mw->list ( { action => 'query',
	    list => 'deletedrevs', 
	    drlimit => '50', 
	    drnamespace => $ns,
	    drprop    => 'revid|user',},
	{ max => 10, hook => \&wiki_add_url2 } )
		|| die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $hash;
}

sub wiki_edit_page {
  my ($self, $title, $text) = @_;
  print "\t-Uploading page for url $title. ". (WikiCommons::get_time_diff) ."\n";
  my $page = $mw->get_page( { title => $title } );
  print "\tCreating a new page for url $title.\n" if ($page->{missing});
  my $timestamp = $page->{timestamp};

  $mw->edit( { action => 'edit', title => $title, text => Encode::decode('utf8', $text) } )
      || die "Could not upload text for $title: ".$mw->{error}->{code} . ': ' . $mw->{error}->{details}."\t". (WikiCommons::get_time_diff) ."\n";
  print "\t+Uploading page for url $title. ". (WikiCommons::get_time_diff) ."\n";
}

sub wiki_import_files {
    my ($self, $file_path, $url) = @_;
    print "\t-Uploading files for url $url.\t". (WikiCommons::get_time_diff) ."\n";
    my @cmd_output = `php "$wiki_site_path/maintenance/importImages.php" --conf "$wiki_site_path/LocalSettings.php" --user="$wiki_user" --overwrite --check-userblock "$file_path"`;
    die "\tError $? for importImages.php.\n" if ($?);
    print "@cmd_output\n";
    print "\t+Uploading files for url $url.\t". (WikiCommons::get_time_diff) ."\n";
}

sub wiki_upload_file {
    my ($self, $files) = @_;
    $mw->{config}->{upload_url} = "$wiki_url/index.php/Special:Upload";
    my @images = ();

    if (ref($files) eq "ARRAY") {
	@images = @$files;
    } elsif (ref($files) eq "") {
	push @images, $files;
    } else {
	die "as\n";
    }
    foreach my $img (@images) {
	print "\t-Start uploading file $img.\n";
	open FILE, "$img" or die $!;
	binmode FILE;
	my ($buffer, $data);
	while ( read(FILE, $buffer, 65536) )  {
	    $data .= $buffer;
	}
	close(FILE);
	my ($name,$dir,$suffix) = fileparse($img, qr/\.[^.]*/);
	$mw->upload( { title => "$name$suffix",
		    summary => 'This is the summary to go on the Image:file.jpg page',
		    data => $data } ) || die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
	print "\t+Start uploading file $img.\n";
    }
}

sub wiki_exists_page {
    my ($self, $title) = @_;
    my $page = $mw->get_page( { title => "$title" } );

    unless ( $page->{'*'} ) {
    return 0;
    }
    return 1;
}

sub wiki_geturl {
    return $wiki_url;
}

sub wiki_move_page {
    my ($self, $title, $new_title) = @_;
    $mw->edit( {
    action => 'move', from => "$title", to => "$new_title" } )
    || die "Could not move url $title to $new_title: ".$mw->{error}->{code} . ': ' . $mw->{error}->{details}."\t". (WikiCommons::get_time_diff)."\n";
}

sub wiki_get_nonredirects {
    my ($self, $ns) = @_;
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'allpages', aplimit=>'5000',
	    apnamespace => "$ns", apfilterredir => "nonredirects" },
	{ max => 1000, hook => \&wiki_add_url } )
		|| die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
}

sub wiki_get_redirects {
    my ($self, $ns) = @_;
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'allpages', aplimit=>'5000',
	    apnamespace => "$ns", apfilterredir => "redirects" },
	{ max => 1000, hook => \&wiki_add_url } )
		|| die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
}

sub wiki_get_all_pages {
    my ($self, $ns) = @_;
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'allpages', aplimit=>'5000',
	    apnamespace => "$ns" },
	{ max => 1000, hook => \&wiki_add_url } )
		|| die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
}

sub wiki_get_unused_images {
    my $self = shift;
    my $arr = wiki_get_all_pages($self, 6);
    my $unused_img = ();
    my $nr_all = 0; my $nr_ok = 0; my $total = scalar @$arr;

    foreach my $image (@$arr) {
	$nr_all++;
        my $pages = wiki_get_pages_using($self, $image, 1);
        if (! defined $pages || scalar(@$pages) == 0) {
	    push @$unused_img, $image;
	    $nr_ok++;
        }
	print "Done $nr_all out of $total, with $nr_ok good.\n" if ($nr_all%1000 == 0);
    }
    return $unused_img;
}

sub wiki_get_pages_using {
    my ($self, $file, $nr) = @_;
    my $limit = 5000; my $max = 1000;
    if (defined $nr ) {
	$limit = $nr; $max = 1;
    }
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'imageusage', iulimit => "$limit",
	    iutitle => "$file" },
	{ max => "$max", hook => \&wiki_add_url } )
		|| die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
}

sub wiki_get_pages_linking_to {
    my ($self, $url) = @_;
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'backlinks', bllimit => "5000",
	    bltitle => "$url" },
	{ max => "1000", hook => \&wiki_add_url } )
		|| die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
} 

sub wiki_get_pages_in_category {
    my ($self, $cat, $nr) = @_;
    my $limit = 5000; my $max = 1000;
    if (defined $nr ) {
	$limit = $nr; $max = 1;
    }
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'categorymembers', iulimit => "$limit",
	    cmtitle => "$cat" },
	{ max => "$max", hook => \&wiki_add_url } )
		|| die $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
} 

sub wiki_add_url {
    my ( $ref) = @_;

    foreach (@$ref) {
	my $info;
	if ( (scalar keys %$_) && defined $_->{'*'}) {
	    $info = $_->{'*'};
	} elsif ((scalar keys %$_) && defined $_->{'name'}) {
	    $info = $_->{name};
	} else {
	    $info = $_->{title};
	}
	chomp $info;
	push @$array, $info;
    }
}

sub wiki_add_url2 {
    my ( $ref) = @_;
    my $q = ();

    foreach (@$ref) {
	push @$q, $_->{'title'};
	push @$q, $_->{'revisions'};
	$hash->{$_->{'ns'}} = $q;
    }
}

return 1;
