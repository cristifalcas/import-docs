package WikiWork;

use warnings;
use strict;

use Mind_work::WikiCommons;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Log::Log4perl qw(:easy);
use MediaWiki::API;
use MediaWiki::Bot;
# get_last($page, $user)
# get_history($pagename[,$limit])
# get_namespace_names()
# http://en.wikipedia.org/w/api.php
# http://www.mediawiki.org/wiki/API:Lists/es

our $wiki_site_path = "/var/www/html/wiki/";
# our $wiki_url = "http://10.0.0.99/wiki";
our $wiki_url = "http://wikitiki.mindsoft.com/wiki";
# our $wiki_url_path = "/wiki";
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
    $mw->{response}->{_request}->{_content}="*** deleted because it can be too big***";
    LOGDIE "Error:
    1. Error code: " . $mw->{error}->{code} . "
    2. Error details: " . Dumper($mw->{error}->{details})."
    3. Error response: " . Dumper($mw->{response})."
    4. Error stacktrace: " . $mw->{error}->{stacktrace}."
    time elapsed"."\t". (WikiCommons::get_time_diff) ."\n";
}

sub new {
    my $class = shift;
    my $self = { user_type => shift};
    INFO "Logging in.\n";
    if (WikiCommons::is_remote ne "yes" ) {
	my ($user, $pass) = ($wiki_user, $wiki_pass);
	($user, $pass) = ($robot_user, $robot_pass) if defined $self->{'user_type'} && $self->{'user_type'} eq "robot";
	$mw = MediaWiki::API->new({ api_url => "$wiki_url/api.php" }, retries  => 3) or LOGDIE "coco";
	$mw->{config}->{on_error} = \&wiki_on_error;
	$mw->login( {lgname => $user, lgpassword => $pass } )
	    || LOGDIE $mw->{error}->{code} . ': ' . $mw->{error}->{details};


	$bmw = MediaWiki::Bot->new();
	$bmw->set_wiki({
	    protocol    => 'http',
	    host        => 'wikitiki.mindsoft.com',
	    path        => 'wiki/',
	});
	$bmw->login({
	    username => $wiki_user,
	    password => $wiki_pass,
	});
    }

    bless($self, $class);
    return $self;
}

sub wiki_get_namespaces {
    my $self = shift;
    INFO "Wiki get namespaces.\n";
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
    my ($timestamp, $file) = split(m/!/, $archive);
    INFO "Wiki delete file $file.\n";
    my $summary = 'deleting old version of image';
    my $res;

    if  ( wiki_exists_page($self, "File:$file") ) {
    $res = $mw->api({
        action   => 'delete',
        title    => "File:$file",
        reason   => $summary,
        oldimage => $archive,
    });
    }
    return $res;
}

sub undelete_image {
    my ($self, $archive) = @_;
    INFO "Wiki undelete file $archive.\n";
    my $res = $bmw->undelete($archive);
    return $res;
}

sub wiki_get_categories {
    my $self = shift;
    INFO "Wiki get categories 1.\n";
    my $res = wiki_get_all_pages($self, 14);
    return $res;
}

sub wiki_get_images {
    my $self = shift;
    INFO "Wiki get all images 1.\n";
    my $res = wiki_get_all_pages($self, 6);
    return $res;
}

sub wiki_get_all_categories {
    my $self = shift;
    INFO "Wiki get categories 2.\n";
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'allcategories', aclimit=>'5000',},
	{ max => 1000, hook => \&wiki_add_url } )
		|| LOGDIE $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
}

sub wiki_get_all_images {
    my $self = shift;
    INFO "Wiki get all images 2.\n";
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'allimages', ailimit=>'5000',},
	{ max => 1000, hook => \&wiki_add_url } )
		|| LOGDIE $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
}

sub wiki_get_page {
  my ($self, $title) = @_;
  INFO "Wiki get page $title.\n";
  my $page = $mw->get_page( { title => $title } );
# INFO Dumper("Got page", $page);
  return $page;
}

sub wiki_get_page_section {
  my ($self, $title, $section) = @_;
  INFO "Wiki get page section.\n";
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
      LOGDIE "Unknown type for images: ".Dumper($title);
    }

    foreach my $url (@img) {
      chomp $url;
      my $page = $mw->get_page( { title => $url } );
      unless ( defined $page->{missing} ) {
#       if ( defined $url && wiki_exists_page($self, $url) && not defined $page->{missing} ) {
	INFO "\tDelete page $url.\n";
	$mw->edit( { action => 'delete', title => $url, reason => 'no longer needed' } )
	|| LOGDIE "Could not delete url $url: ".$mw->{error}->{code} . ': ' . $mw->{error}->{details}."\t". (WikiCommons::get_time_diff) ."\n";
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
		|| LOGDIE $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $hash;
}

sub wiki_edit_page {
  my ($self, $title, $text) = @_;
  INFO "\t-Uploading page for url $title. ". (WikiCommons::get_time_diff) ."\n";
  my $page = $mw->get_page( { title => $title } );
  INFO "\t Creating a new page for url $title.\n" if ($page->{missing});
  my $timestamp = $page->{timestamp};

  $mw->edit( { action => 'edit', title => $title, text => Encode::decode('utf8', $text) } )
      || LOGDIE "Could not upload text for $title: ".$mw->{error}->{code} . ': ' . $mw->{error}->{details}."\t". (WikiCommons::get_time_diff) ."\n";
  INFO "\t+Uploading page for url $title. ". (WikiCommons::get_time_diff) ."\n";
}

sub wiki_import_files {
    my ($self, $file_path, $url) = @_;
    ## need in /etc/sudoers to have "wiki ALL=(apache) NOPASSWD: ALL"
    INFO "\t-Uploading files ($file_path) for url $url.\t". (WikiCommons::get_time_diff) ."\n";
    my $cmd_output = `sudo -u apache php "$wiki_site_path/maintenance/importImages.php" --conf "$wiki_site_path/LocalSettings.php" --user="$wiki_user" --check-userblock "$file_path" --overwrite`;
    LOGDIE "\tError $? for importImages.php: ".Dumper($cmd_output) if ($?);
    INFO "$cmd_output\n";
    INFO "\t+Uploading files for url $url.\t". (WikiCommons::get_time_diff) ."\n";
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
	LOGDIE "as\n";
    }
    foreach my $img (@images) {
	INFO "\t-Start uploading file $img.\n";
	open FILE, "$img" or LOGDIE $!;
	binmode FILE;
	my ($buffer, $data);
	while ( read(FILE, $buffer, 65536) )  {
	    $data .= $buffer;
	}
	close(FILE);
	my ($name,$dir,$suffix) = fileparse($img, qr/\.[^.]*/);
	$mw->upload( { title => "$name$suffix",
		    summary => 'This is the summary to go on the Image:file.jpg page',
		    data => $data } ) || LOGDIE $mw->{error}->{code} . ': ' . $mw->{error}->{details};
	INFO "\t+Start uploading file $img.\n";
    }
}

sub wiki_exists_page {
    my ($self, $title) = @_;
    TRACE "Wiki check if page $title exists.\n";
    my $page = $mw->get_page( { title => $title } );
# INFO Dumper($page->{'timestamp'});
    return 0 unless ( $page->{'*'} ) ;
    return 1;
}

sub wiki_get_page_timestamp {
    my ($self, $title) = @_;
    my $page = $mw->get_page( { title => $title } );
    return $page->{'timestamp'};
}

sub wiki_geturl {
    return $wiki_url;
}

sub wiki_move_page {
    my ($self, $title, $new_title) = @_;
    INFO "Wiki move page $title to $new_title.\n";
    $mw->edit( {
    action => 'move', from => "$title", to => "$new_title" } )
    || LOGDIE "Could not move url $title to $new_title: ".$mw->{error}->{code} . ': ' . $mw->{error}->{details}."\t". (WikiCommons::get_time_diff)."\n";
}

sub wiki_get_nonredirects {
    my ($self, $ns) = @_;
    DEBUG "Wiki get non redirects for ns $ns.\n";
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'allpages', aplimit=>'5000',
	    apnamespace => "$ns", apfilterredir => "nonredirects" },
	{ max => 1000, hook => \&wiki_add_url } )
		|| LOGDIE $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
}

sub wiki_get_redirects {
    my ($self, $ns) = @_;
    DEBUG "Wiki get redirects for ns $ns.\n";
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'allpages', aplimit=>'5000',
	    apnamespace => "$ns", apfilterredir => "redirects" },
	{ max => 1000, hook => \&wiki_add_url } )
		|| LOGDIE $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
}

sub wiki_get_all_pages {
    my ($self, $ns) = @_;
    INFO "Wiki get all pages with ns $ns.\n";
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'allpages', aplimit=>'5000',
	    apnamespace => "$ns" },
	{ max => 1000, hook => \&wiki_add_url } )
		|| LOGDIE $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
}

sub wiki_get_unused_images {
    my $self = shift;
    INFO "Wiki get unused images.\n";

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
	INFO "Done $nr_all out of $total, with $nr_ok good.\n" if ($nr_all%1000 == 0);
    }
    return $unused_img;
}

sub wiki_get_pages_using {
    my ($self, $file, $nr) = @_;
    INFO "Wiki get pages using file $file.\n";

    my $limit = 5000; my $max = 1000;
    if (defined $nr ) {
	$limit = $nr; $max = 1;
    }
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'imageusage', iulimit => "$limit",
	    iutitle => "$file" },
	{ max => "$max", hook => \&wiki_add_url } )
		|| LOGDIE $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
}

sub wiki_get_pages_linking_to {
    my ($self, $url) = @_;
    INFO "Wiki pages linking to $url.\n";
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'backlinks', bllimit => "5000",
	    bltitle => "$url" },
	{ max => "1000", hook => \&wiki_add_url } )
		|| LOGDIE $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
} 

sub wiki_get_pages_in_category {
    my ($self, $cat, $nr) = @_;
    DEBUG "Wiki pages in category $cat.\n";
    my $limit = 5000; my $max = 1000;
    if (defined $nr ) {
	$limit = $nr; $max = 1;
    }
    $array = ();
    $mw->list ( { action => 'query',
	    list => 'categorymembers', iulimit => "$limit",
	    cmtitle => "$cat" },
	{ max => "$max", hook => \&wiki_add_url } )
		|| LOGDIE $mw->{error}->{code} . ': ' . $mw->{error}->{details};
    return $array;
} 

sub wiki_add_url {
    my ( $ref) = @_;

    INFO "Adding to list ".(scalar @$ref)." pages.\n";
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
