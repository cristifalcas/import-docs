package WikiCommons;

use warnings;
use strict;

use File::Path qw(make_path remove_tree);
use Unicode::Normalize 'NFD','NFC','NFKD','NFKC';
use File::Basename;
use File::Copy;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Digest::MD5 qw(md5 md5_hex md5_base64);
use XML::Simple;
use LWP::UserAgent;
use Log::Log4perl qw(:easy);
use Encode;

our $start_time = 0;
our $clean_up = {};
our $url_sep = " -- ";
our $remote_work = "no";
our $real_path;
our $customers = {};

sub set_real_path {
    $real_path = shift;
}

sub svn_list {
    my ($url, $svn_pass, $svn_user) = @_;
    my $q_url = quotemeta $url;
    my $output = `svn list --non-interactive --no-auth-cache --trust-server-cert --password "$svn_pass" --username "$svn_user" $q_url 2>&1`;
    if ($?) {
	INFO "\tError $? for svn list.\n";
	return undef;
    }
    $output =~ s/\/$//gm;
    return $output;
}

sub svn_checkout {
    my ($url, $local, $svn_pass, $svn_user) = @_;
    my $list = svn_list($url, $svn_pass, $svn_user);
    return undef if undef $list;
    my $output = `svn co --non-interactive --no-auth-cache --trust-server-cert --password "$svn_pass" --username "$svn_user" "$url" "$local"`; # 2> /dev/null
    if ($?) {
	LOGDIE "\tError $? for svn checkout $url to $local.\n";
	return undef;
    }
    INFO "$output\n";
    return 1;
}


sub svn_info {
    my ($url, $svn_pass, $svn_user) = @_;
    my $q_url = quotemeta $url;
    my $output = `svn info --non-interactive --no-auth-cache --trust-server-cert --password "$svn_pass" --username "$svn_user" $q_url 2>&1`; 
    if ($?) {
	INFO "\tError $? for svn info.\n";
	return undef;
    }
    $output =~ s/\/$//gm;
    return $output;
}

sub http_get {
    my ($url_path, $local_path, $svn_user, $svn_pass) = @_;
    my $ua = LWP::UserAgent->new;
    my $count = 1;
    my $content = "";
    my ($name,$dir,$suffix) = fileparse($url_path, qr/\.[^.]*/);
    my $request = HTTP::Request->new(GET => "$dir");
    $request->authorization_basic("$svn_user", "$svn_pass") if defined $svn_user && defined $svn_pass;

    INFO "\t-Get from url $url_path.\n";
    my $retries = 0;
    while ($retries < 3) {
	$request->uri( $url_path );
	my $response = $ua->request($request);
	if ($response->is_success) {
	    $content .= $response->content;
# 	    INFO $response->decoded_content;
	    last;
	}else {
	    if ($response->status_line eq "404 Not Found") {
		return;
	    } else {
		INFO Dumper($response->status_line) ."\tfor file $url_path\n" ;
		$retries++;
	    }
	}
    }
    LOGDIE "Unknown error when retrieving file $url_path.\n" if $retries >= 3;
    my $res = "";
    if ( defined $local_path && $local_path !~ m/^\s*$/i ) {
	write_file("$local_path/$name$suffix", $content);
	$res = "$local_path/$name$suffix";
    } else {
	$res = $content;
    }
    INFO "\t+Get from url $url_path.\n";
    return "$res";
}

sub is_remote {
    my $q=shift;
    $remote_work = $q || $remote_work;
    return $remote_work;
}

sub xmlfile_to_hash {
    my $file = shift;
    my $xml = new XML::Simple;
    return $xml->XMLin("$file");
}

sub hash_to_xmlfile {
    my ($hash, $name, $root_name) = @_;
    $root_name = "out" if ! defined $root_name;
    my $xs = new XML::Simple();
    my $xml = $xs->XMLout($hash,
		    NoAttr => 1,
		    RootName=>$root_name,
		    OutputFile => $name
		    );
}

sub cleanup {
    my $dir = shift;

    foreach my $key (keys %$clean_up) {
	if ($clean_up->{"$key"} eq "file") {
# 	    unlink("$key") or LOGDIE "Could not delete the file $key: ".$!."\n";
	    unlink("$key") or return 1;
	    delete $clean_up->{"$key"};
	}
    }
    foreach my $key (keys %$clean_up) {
	if ($clean_up->{$key} eq "dir") {
	    remove_tree("$key");
	    delete $clean_up->{"$key"};
	} else {
# 	    LOGDIE "caca $clean_up->{$key} for $key\n";
	    INFO "caca $clean_up->{$key} for $key\n";
	    return 1;
	}
    }
    return 1 if scalar keys %$clean_up;
    $clean_up = {};
    return 0;
}

sub copy_dir {
    my ($from_dir, $to_dir) = @_;
    opendir my($dh), $from_dir or LOGDIE "Could not open dir '$from_dir': $!";
    for my $entry (readdir $dh) {
#         next if $entry =~ /$regex/;
        my $source = "$from_dir/$entry";
        my $destination = "$to_dir/$entry";
        if (-d $source) {
	    next if $source =~ "\.?\.";
            mkdir $destination or LOGDIE "mkdir '$destination' failed: $!" if not -e $destination;
            copy_dir($source, $destination);
        } else {
            copy($source, $destination) or LOGDIE "copy failed: $source to $destination $!";
        }
    }
    closedir $dh;
    return;
}

sub move_dir {
    my ($src, $trg) = @_;
    LOGDIE "\tTarget $trg is a file.\n" if (-f $trg);
    makedir("$trg", 1) if (! -e $trg);
    opendir(DIR, "$src") || die("Cannot open directory $src.\n");
    my @files = grep { (!/^\.\.?$/) } readdir(DIR);
    closedir(DIR);
    foreach my $file (@files){
	move("$src/$file", "$trg/$file") or LOGDIE "Move file $src/$file to $trg failed: $!\n";
    }
    remove_tree("$src") || LOGDIE "Can't remove dir $src.\n";
}

sub write_file {
    my ($path,$text, $remove) = @_;
    $remove = 0 if not defined $remove;
    my ($name,$dir,$suffix) = fileparse($path, qr/\.[^.]*/);
    add_to_remove("$dir/$name$suffix", "file") if $remove ne 0;
    INFO "\tWriting file $name$suffix.\t". get_time_diff() ."\n";
    open (FILE, ">$path") or LOGDIE "at generic write can't open file $path for writing: $!\n";
    ### don't decode/encode to utf8
    print FILE "$text";
    close (FILE);
}

sub get_time_diff {
    return (time() - $start_time);
}

sub get_urlsep {
    return "$url_sep";
}

sub makedir {
    my ($dir, $no_extra) = @_;
    my ($name_user, $pass_user, $uid_user, $gid_user, $quota_user, $comment_user, $gcos_user, $dir_user, $shell_user, $expire_user) = getpwnam scalar getpwuid $<;
    my $err;
    if (defined $no_extra) {
	make_path ("$dir", {error => \$err});
    } else {
	make_path ("$dir", {owner=>"$name_user", group=>"nobody", error => \$err});
    }
    if (@$err) {
	for my $diag (@$err) {
	    my ($file, $message) = %$diag;
	    if ($file eq '') { INFO "general error: $message.\n"; }
	    else { INFO "problem unlinking $file: $message.\n"; }
	}
	LOGDIE "Can't make dir $dir: $!.\n";
    }
    LOGDIE "Dir not created.\n" if ! -d $dir;
}

sub add_to_remove {
    my ($file, $type) = @_;
    $clean_up->{$file} = "$type";
}

sub normalize_text {
    my $str = shift;
    ## from http://www.ahinea.com/en/tech/accented-translate.html
    for ( $str ) {  # the variable we work on
	##  convert to Unicode first
	##  if your data comes in Latin-1, then uncomment:
	$_ = Encode::decode( 'utf8', $_ );

	s/\xe4/ae/g;  ##  treat characters ä ñ ö ü ÿ
	s/\xf1/ny/g;  ##  this was wrong in previous version of this doc
	s/\xf6/oe/g;
	s/\xfc/ue/g;
	s/\xff/yu/g;
	## various apostrophes   http://www.mikezilla.com/exp0012.html
	s/\x{02B9}/\'/g;
	s/\x{2032}/\'/g;
	s/\x{0301}/\'/g;
	s/\x{02C8}/\'/g;
	s/\x{02BC}/\'/g;
	s/\x{2019}/\'/g;

	$_ = NFD( $_ );   ##  decompose (Unicode Normalization Form D)
	s/\pM//g;         ##  strip combining characters

	# additional normalizations:

	s/\x{00df}/ss/g;  ##  German beta “ß” -> “ss”
	s/\x{00c6}/AE/g;  ##  Æ
	s/\x{00e6}/ae/g;  ##  æ
	s/\x{0132}/IJ/g;  ##  ?
	s/\x{0133}/ij/g;  ##  ?
	s/\x{0152}/Oe/g;  ##  Œ
	s/\x{0153}/oe/g;  ##  œ

	tr/\x{00d0}\x{0110}\x{00f0}\x{0111}\x{0126}\x{0127}/DDddHh/; # ÐÐðdHh
	tr/\x{0131}\x{0138}\x{013f}\x{0141}\x{0140}\x{0142}/ikLLll/; # i??L?l
	tr/\x{014a}\x{0149}\x{014b}\x{00d8}\x{00f8}\x{017f}/NnnOos/; # ???Øø?
	tr/\x{00de}\x{0166}\x{00fe}\x{0167}/TTtt/;                   # ÞTþt

	s/[^\0-\x80]//g;  ##  clear everything else; optional
    }
    return Encode::encode( 'utf8', $str );  ;
}

sub get_file_md5 {
    my ($doc_file, $empty_if_missing) = @_;
    TRACE "\tGetting md5 for $doc_file\n";
    return "" if defined $empty_if_missing && $empty_if_missing && ! -f $doc_file;
    my $doc_md5;
    eval{
    open(FILE, $doc_file) or LOGDIE "Can't open '$doc_file' for md5: $!\n";
    binmode(FILE);
    $doc_md5 = Digest::MD5->new->addfile(*FILE)->hexdigest;
    close(FILE);
    };
    if ($@) {
	ERROR "\tError in getting md5:".Dumper($@);
	$doc_md5 = get_file_sha($doc_file);
    }
    return $doc_md5;
}

sub get_file_sha {
    my $doc_file = shift;
    LOGDIE "Not a file: $doc_file\n" if ! -f $doc_file;
    use Digest::SHA qw(sha1_hex);
    my $sha = Digest::SHA->new();
    $sha->addfile($doc_file);
    return $sha->hexdigest;;
}

sub capitalize_string {
    my ($str,$type) = @_;
    if ($type eq "first") {
	$str =~ s/\b(\w)/\U$1/g;
    } elsif ($type eq "all") {
	$str =~ s/([\w']+)/\u\L$1/g;
    } elsif ($type eq "small") {
	$str =~ s/([\w']+)/\L$1/g;
    } elsif ($type eq "onlyfirst") {
	$str =~ s/\b(\w)/\U$1/;
    } else {
	LOGDIE "Capitalization: first (first letter is capital and the rest remain the same), small (all letters to lowercase) or all (only first letter is capital, and the rest are lowercase).\n";
    }
    return $str;
}

sub fix_name {
    my ($name, $customer, $big_ver, $main, $ver, $ver_sp, $ver_id) = @_;
    my $fixed_name = $name;
    $fixed_name = normalize_text($fixed_name);

    $fixed_name =~ s/^\s?$customer[-_ \t]//i;
    $fixed_name =~ s/[-_ \t]$customer\s*$//i;

    $fixed_name =~ s/^\s?(MIND[-_ \t]?)?iphonex//i;
    $fixed_name =~ s/^\s?(MIND[-_ \t]?)?MINDBil[l]?//i;
    $fixed_name =~ s/^\s?mind[-_ \t]?//i;

    $fixed_name =~ s/^\s?$customer[-_ \t]//i;
    $fixed_name =~ s/[-_ \t]$customer\s*$//i;

    $fixed_name =~ s/([[:digit:]])_/$1\./gi;
    $fixed_name =~ s/[\[\]\/#_\"]/ /g;
#     $fixed_name =~ s/_/ /gi;
    my $yet_another_version_style = $ver;
    if (defined $ver && defined $main) {
	$fixed_name =~ s/(^\s?[v]?$ver\s*$ver_id\s*$ver_sp\s+)|(\s+[v]?$ver\s*$ver_id\s*$ver_sp\s*$)//i;
	$fixed_name =~ s/(^\s?[v]?$ver\s*$ver_sp\s+)|(\s+[v]?$ver\s*$ver_sp\s*$)//i;
	$fixed_name =~ s/(^\s?[v]?$ver\s*$ver_id\s+)|(\s+[v]?$ver\s*$ver_id\s*$)//i;
	$fixed_name =~ s/(^\s?[v]?$ver\s+)|(\s+[v]?$ver\s*$)//i;
	$fixed_name =~ s/(^\s?[v]?$main\s+)|(\s+[v]?$main\s*$)//i;
	$fixed_name =~ s/(^\s?[v]?$big_ver\s+)|(\s+[v]?$big_ver\s*$)//i;
	my $aver = $ver;
	my $amain = $main;
	$aver =~ s/\.//g;
	$amain =~ s/\.//g;
	$fixed_name =~ s/(^\s?[v]?$aver\s+)|(\s+[v]?$aver\s*$)//i;
	$fixed_name =~ s/(^\s?[v]?$amain\s+)|(\s+[v]?$amain\s*$)//i;
    }

    $fixed_name =~ s/^\s*-\s+//;
    $fixed_name =~ s/\s+/ /g;

    $fixed_name =~ s/(^\s*)|(\s*$)//g;
    $fixed_name =~ s/\s+/ /g;

    return $fixed_name;
}

sub check_vers {
    my ($main, $ver) = @_;
    LOGDIE "main $main or ver $ver is not defined.\n" if (! defined $main || ! defined $ver);
#     ver:
#     V7.00.001 SP28 DEMO
#     V5.01.008OMP
#     V5.31.006 GN SP01.004.2
#     User Manuals

#     main:
#     5.31.006
#     V6.01.003 SP40
#
    my $ver_fixed = ""; my $ver_sp = ""; my $ver_id = ""; my $main_sp = "";
    my $main_v = ""; my $ver_v = ""; my $big_ver = "";

    my $regexp_main = qr/^\s*v?[0-9]{1,}(\.[0-9]{1,})*\s*([a-z0-9 ]{1,})?\s*(SP\s*[0-9]{1,}(\.[0-9]{1,})*)?$/is;
    my $regexp_ver = qr/^\s*v?[0-9]{1,}(\.[0-9]{1,})*\s*([a-z0-9 ]{1,})?\s*(SP\s*[0-9]{1,}(\.[0-9]{1,})*)?\s*(demo)?\s*$/is;

    LOGDIE "Main version $main is not correct.\n" if $main !~ m/$regexp_main/i;
#     LOGDIE "Ver version $ver is not correct.\n" if $ver !~ m/$regexp_ver/i;
    $ver =$main if $ver !~ m/$regexp_ver/i;

    ### make versions like N.NN and remove any leading v
    $main = $main."0" if $main =~ m/^v?[[:digit:]]{1,}\.[[:digit:]]$/i;
    $main = $main.".00" if $main =~ m/^v?[[:digit:]]{1,}$/i;
    $main =~ s/\s*v//i;
    $ver = $ver."0" if $ver =~ m/^v?[[:digit:]]{1,}\.[[:digit:]]$/i;
    $ver = $ver.".00" if $ver =~ m/^v?[[:digit:]]{1,}$/i;
    $ver =~ s/\s*v//i;

    ### extract SPN.NN.NNN and remove it from versions
    $main_sp = $2 if $main =~ m/^(.*)?(SP\s*[0-9]{1,}(\.[0-9]{1,})*)(.*)?$/i;
    $main =~ s/$main_sp// if $main_sp ne "";
    $ver_sp = $2 if $ver =~ m/^(.*)?(SP\s*[0-9]{1,}(\.[0-9]{1,})*)(.*)?$/i;
    $ver =~ s/\s*$ver_sp\s*// if $ver_sp ne "";

    ### from main keep only N.NN
    if ($main =~ m/^([0-9]{1,}\.[0-9]{2})(\.[0-9]{1,})*\s*([a-z0-9 ]{1,})?(.*)?$/i){
	$main_v = "$1";
    }

    ### from ver extract any identificator
    if ($ver =~ m/^([0-9]{1,}(\.[0-9]{1,})*)\s*([a-z0-9 ]{1,})?$/i){
	$ver_v = "$1";
	$ver_id = "$3" if defined $3;
    }

    ### if we don't have an identificator, ver_fixed will be main, otherwise $ver
    if ($ver_id ne "" ){
	$ver_fixed = "$ver_v $ver_id";
    } else {
	$ver_fixed = "$main_v";
    }

    $big_ver = $1 if $main =~ m/^([0-9]{1,})((\.[0-9]{1,})*)(.*)$/i;

    $big_ver =~ s/(^\s*|\s*$)//g;
    $main_v =~ s/(^\s*|\s*$)//g;
    $ver_v =~ s/(^\s*|\s*$)//g;
    $ver_fixed =~ s/(^\s*|\s*$)//g;
    $ver_sp =~ s/(^\s*|\s*$)//g;

    LOGDIE "Main $main_v is not like version $ver_v.\n" if $ver_v !~ m/^$main_v/;

    return $big_ver, $main_v, $ver_v, $ver_fixed, $ver_sp, $ver_id;
}

sub generate_html_file {
    my ($doc_file, $type, $thread) = @_;
    INFO "\t## using thread ".Dumper($thread);
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);

if (!is_file_rtf($doc_file)){
    use HTML::TextToHTML;
    my $conv = new HTML::TextToHTML();
    $conv->txt2html(infile=>[$doc_file],
			outfile=>"$dir/$name.html",
			title=>"$name",
			mail=>1,
	  ]);
    return;
}


    my $status;
    ## filters http://cgit.freedesktop.org/libreoffice/core/tree/filter/source/config/fragments/filters
    my $filters = { "html" => $suffix =~ m/xlsx?/i ? "html:HTML (StarCalc)" : "html:HTML (StarWriter)",
		    "pdf"  => "pdf:impress_pdf_Export",
		    "swf"  => "swf:impress_flash_Export",
		    "txt"  => "txt:TEXT (StarWriter_Web)",
		  };
    my $lo_tmp_dir = "/tmp/wiki_libreoffice_$thread";
    ## I removed libreoffice from the system.
    my @lo_args = ("--invisible", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "--convert-to", $filters->{$type}, "--outdir", "$dir", "$doc_file", "-env:UserInstallation=file://$lo_tmp_dir");
    my $commands = {
	  "1. latest office" 		=> ["/opt/libreoffice4.0/program/soffice", "--headless", @lo_args], 
	  "2. latest office with X" 	=> ["/opt/libreoffice4.0/program/soffice", "--display", ":10235", @lo_args], 
	  "3. unoconv" 			=> ["python", "$real_path/convertors/unoconv", "-f", "$type", "$doc_file"],
	  "4. our office" 		=> ["/opt/libreoffice3.6/program/soffice", "--headless", @lo_args], 
	  "5. our office with X" 	=> ["/opt/libreoffice3.6/program/soffice", "--display", ":10235", @lo_args], 
# 	  "6. system office with X" => ["libreoffice", "--invisible", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "--convert-to", $filters->{$type}, "--outdir", "$dir", "$doc_file"],
# 	  "7. system office" => [@change_user, "libreoffice", "--headless", "--invisible", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "--convert-to", $filters->{$type}, "--outdir", "$dir", "$doc_file"],
# 	  "8. our office old with X" => [@change_user, "/opt/libreoffice3.4/program/soffice", "--invisible", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "--convert-to", $filters->{$type}, "--outdir", "$dir", "$doc_file"], 
# 	  "9. our office old " => [@change_user, "/opt/libreoffice3.4/program/soffice", "--headless", "--invisible", "--nodefault", "--nologo", "--nofirststartwizard", "--norestore", "--convert-to", $filters->{$type}, "--outdir", "$dir", "$doc_file"], 
	};

    INFO "\t-Generating $type file from $name$suffix.\t". (get_time_diff) ."\n\t\t$doc_file\n";
    system("Xvfb :10235 -screen 0 1024x768x16 &> /dev/null &"); ## if we don't use headless
#     system("python $real_path/convertors/unoconv -l &"); ## start a listener
    my $max_wait_time = 150;
    $max_wait_time = 30 if (-s $doc_file < 100000);
    foreach my $key (sort keys %$commands) {
	INFO "\tTrying to use $key.\t". (get_time_diff) ."\n";
	my $pids_to_kill = `ps -ef | egrep soffice.bin\\|oosplash.bin | grep -v grep | grep "$lo_tmp_dir" | gawk '{print \$2}'`;
	if ($pids_to_kill =~ m/^\s*$/) {
	    INFO "No office to kill.\n";
	} else {
	    INFO "killing office processes $pids_to_kill.\n";
	    if ($pids_to_kill !~ m/^[0-9 ]+$/) {
		ERROR "Strange stuff to kill: $pids_to_kill.\n";
	    } else {
		`kill $pids_to_kill`;
	    }
	}
# 	`kill -9 \$(ps -ef | egrep soffice.bin\\|oosplash.bin | grep -v grep | grep "$lo_tmp_dir" | gawk '{print \$2}') &>/dev/null`;
	remove_tree($lo_tmp_dir);
	sleep 1;
	eval {
	  local $SIG{ALRM} = sub { die "alarm\n" };
	  alarm $max_wait_time;
	  INFO "Running: ".(join ' ', @{$commands->{$key}}).".\n";
	  system(@{$commands->{$key}});
	  alarm 0;
	};
	$status = $@;

	last if ! $status && -f "$dir/$name.$type";
	$max_wait_time = $max_wait_time <= 60 ? 300 : $max_wait_time * 2;
	ERROR "\t\tError: $status. Try again with next command.\t". (get_time_diff) ."\n";
    }

    INFO "\t+Generating $type file from $name$suffix.\t". (get_time_diff) ."\n";
#     return $status;
}

sub is_file_rtf {
    my $file_name = shift;
    open(FOO, $file_name) or die $!;
    my $five_bytes;
    my $len = sysread FOO, $five_bytes, 5;
    close FOO; 
    return $four_bytes eq '{\rtf';
}

sub reset_time {
    $start_time = time();
}

sub array_diff {
    INFO "-Compute difference and uniqueness.\n";
    my ($arr1, $arr2) = @_;
    my %seen = (); my @uniq1 = grep { ! $seen{$_} ++ } @$arr1; $arr1 = \@uniq1;
    %seen = (); my @uniq2 = grep { ! $seen{$_} ++ } @$arr2; $arr2 = \@uniq2;

    my (@only_in_arr1, @only_in_arr2, @common) = ();
## union: all, intersection: common, difference: unique in a and b
    my (@union, @intersection, @difference) = ();
    my %count = ();
    foreach my $element (@$arr1, @$arr2) { $count{"$element"}++ }
    foreach my $element (sort keys %count) {
	push @union, $element;
	push @{ $count{$element} > 1 ? \@intersection : \@difference }, $element;
# 	push @difference, $element if $count{$element} <= 1;
    }
    INFO "\tdifference done.\n";

    my $arr1_hash = ();
    $arr1_hash->{$_} = 1 foreach (@$arr1);

    foreach my $element (@difference) {
	if (exists $arr1_hash->{$element}) {
	    push @only_in_arr1, $element;
	} else {
	    push @only_in_arr2, $element;
	}
    }
    INFO "+Compute difference and uniqueness.\n";
    return \@only_in_arr1,  \@only_in_arr2,  \@intersection;
}

sub get_correct_customer{
    my $name = shift;
    $name =~ s/(^\s+)|(\s+$)//g;
    return "" if $name =~ m/^\s*$/;

    return "Afripa" if $name eq "Afripa Telecom" || $name =~ m/afripa/i;;
    return "SIW" if $name =~ m/^SI$/i;
    return "VDC" if $name eq "VTI";
    return "TELEFONICA PERU" if $name eq "Telefonica Del Peru" || $name eq "Telefonica - Peru";
    return "Budget Tel" if $name eq "Budgettel";
    return "Telecom-Colombia" if $name eq "colombia" || $name eq "Telecom Kolumbia" || $name eq "Telecom - Colombia";
    return "MSTelcom" if $name eq "MSTelecom";
    return "Mobee" if $name eq "MobeeTel" || $name =~ m/^mobi\s*/i;
    return "CWP" if $name eq "CWPanama" || $name eq "Cable & Wireless" || $name eq "Bell South Panama" || $name eq "BellSouth Panama"
	    || $name eq "Bell South";
    return "alcatel" if $name eq "Vendors: Alcatel" || $name eq "Alcatel / NerDring";
    return "3KInt" if $name eq "3K intl" || $name eq "MIND-3KInt"; #$name eq "MIND-SR 3KInt" ||
    return "H3G Italy" if $name eq "H3G" || $name eq "h3g" || $name eq "H3G - IBM" || $name eq "H3g" || $name eq "H3G Omnitel" || $name eq "H3G Omnitel" || $name eq "H3G Italiano" || $name eq "Italy and HK" || $name eq "H3G-Italy" || $name eq "h3g iatly"
	    || $name eq "H3G through IBM" || $name eq "H3G Itayl" || $name eq "Italy" || $name eq "H3G - Italy"
	    || $name eq "H3G Italy TB" || $name eq "Service Call H3G Italy";
    return "H3G-UK" if $name eq "H3G UK" || $name eq "H3G UK and H3G HK" || $name eq "H3G UK and HK";
    return "H3G-HK" if $name eq "H3G Honk Kong" || $name eq "HK" || $name eq "H3G HK" || $name eq "H3G - HK";
    return "Vivodi" if $name eq "Vivody" || $name eq "Vivodi - All";
    return "Teledome" if $name eq "Teledom" || $name eq "Teledome Greece" || $name eq "Teledome. probably all" || $name eq "teleodme"
	    || $name eq "Teledome + All";
    return "Lucent" if $name eq "Lucent Customers";
    return "VocalTec" if $name eq "VocalTec Yael Siaki Lab" || $name eq "VT";
    return "TTCom" if $name eq "TotalCom";
    return "Flat Wireless" if $name eq "Flat" || $name eq "flat";
    return "Moldtelecom" if $name eq "MoldTel" || $name eq "Moltelecom" || $ name eq "Moldtel";
    return "SMTC" if $name eq "Telem";
    return "SINGTEL" if $name eq "SigTel" || $name eq "Singtel UAT" || $name eq "Singel" || $name eq "SINGTEL UAT";# || $name eq "Sing Tel";
    return "France Telecom" if $name eq "FT Salvador" || $name eq "FT salvador" || $name eq "France Telecom4_El Salvador"
	    || $name eq "France Telecom El-Salvador";
    return "Kocnet" if $name eq "Koçnet" || $name eq "Kocent";
    return "ITN" if $name eq "ITN Nigeria" || $name eq "ITN nigeria" || $name eq "INT";
    return "CTIBS" if $name eq "CTI Billng" || $name eq "Cti billing";
    return "CAT" if $name eq "CAT (& all Vocaltec customers)" || $name eq "CAT and others" || $name eq "CAT Thailand";
    return "AMT Group" if $name eq "AMT";
    return "AZUL" if $name eq "US lab (for Azultel)" || $name eq "Azultel - US" || $name eq "Azultel +  ALL";# || $name eq "AzulTel" || $name eq "Azultel" || $name eq "azultel";
    return "BTL" if $name eq "Belize";
    return "Intelco" if $name eq "Intelco Belize" || $name eq "Belize Intelco" || $name eq "intelco 5.21" || $name eq "Intelco (Belize)"
	    || $name eq "intelco belize" || $name eq "Intelco - Belize" || $name eq "Itelco" || $name eq "Intelco belize";
    return "Artelecom" if $name eq "Artelecom + All" || $name eq "Artelecom Romania" || $name eq "Artelecome"; # || $name eq "AR Telecom"
    return "sabanchi" if $name eq "Sabanci" || $name eq "sabanci" || $name eq "Sabnci Telecom" || $name eq "sbanci" || $name eq "Sbanci";
    return "Bynet" if $name eq "BNet";
    return "Adisam" if $name eq "Adisam Romania";
    return "OPTIMA" if $name eq "optima russia" || $name eq "Optima Russia";
    return "INC" if $name eq "Inclarity UK";
    return "cabletel" if $name eq "Cabeltel" || $name eq "CabelTel";
    return "Netcom - IPTEL" if $name eq "IPTEL-SL" || $name eq "IPTEL";
    return "CTV" if $name eq "CTVTelecomPanama";
    return "callsat" if $name eq "CallSat Cyprus";
    return "QTSC" if $name eq "UAT + QTSC";
    return "ViaeroEsc" if $name eq "ViaroEsc";
    return "US-ESCALATION" if $name eq "US Escallation";
    return "Billing" if $name eq "SRG + Billing";
    return "SMART" if $name eq "SmartPCS";
    return "Pelephone" if $name =~ m/^Pelephone$/i;
    return "Eastlink" if $name =~ m/^Eastlink$/i;
    return "Alon" if $name =~ m/^(alon|AlonCellular|Alon Cellular)/i;
    return "United" if $name =~ m/^(united)$/i;

    if ( ! scalar keys %$customers ){
	$customers = WikiCommons::xmlfile_to_hash ("$real_path/customers.xml");
	foreach my $nr (sort keys %$customers){
	    my $new_nr = $nr;
	    $new_nr =~ s/^nr//;
	    $customers->{$new_nr} = $customers->{$nr};
	    delete $customers->{$nr};
	}
    }

    my $crm_name = "";
    my $is_ok = 0;
    foreach my $nr (sort { $a <=> $b } keys %$customers){
	my $crt_name = $customers->{$nr}->{'displayname'};
	my $alt_name = $name;
	$alt_name =~ s/( |_|-)//g;

	if ($crt_name =~ m/^$name$/i){
	    $crm_name = $crt_name;
	    $is_ok = 1;
	    next;
	} elsif ($crt_name =~ m/^$alt_name$/i){
	    $crm_name = $crt_name;
	    $is_ok = 1;
	    next;
	}

	$crt_name = $customers->{$nr}->{'name'};
	if ($crt_name =~ m/^$name$/i){
	    $crm_name = $customers->{$nr}->{'displayname'};
	    $is_ok = 1;
	} elsif ($crt_name =~ m/^$alt_name$/i){
	    $crm_name = $customers->{$nr}->{'displayname'};
	    $is_ok = 1;
	}
    }

    return undef if ( ! $is_ok );
    return $crm_name;
}

sub shouldSkipFile {
    my ($url, $file) = @_;
    my $ret = 0;
#     $ret = 1 if $url eq "CMS:PhonEX ONE 2.30 Installation Technical Guide" && -s $file == 10507264;
#     $ret = 1 if $url eq "CMS:PhonEX ONE 2.30 Installation Technical Guide For Red Box" && -s $file == 5887087;
#     $ret = 1 if $url eq "CMS:PhonEX ONE 2.31 FAQs" && -s $file == 7906304;
#     $ret = 1 if $url eq "CMS:PhonEX ONE 2.31 Installation Technical Guide" && -s $file == 9917952;
#     $ret = 1 if $url eq "CMS:PhonEX ONE 2.31 Installation Technical Guide For Red Box" && -s $file == 8760832;
    $ret = 1 if $url eq "XXX" && -s $file == 100;
    $ret = 1 if $url eq "XXX" && -s $file == 100;
    INFO "Skipping file $file with url $url. They should be saved in docx with Microsoft Word and copied instead of the original doc.\n" if $ret==1;
    return $ret;
}

return 1;
