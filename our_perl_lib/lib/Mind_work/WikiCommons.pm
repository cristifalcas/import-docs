package WikiCommons;

use warnings;
use strict;

use File::Path qw(make_path remove_tree);
use Unicode::Normalize 'NFD','NFC','NFKD','NFKC';
use File::Basename;
use File::Copy;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use XML::Simple;
use LWP::UserAgent;
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
    my $output = `svn list --non-interactive --no-auth-cache --trust-server-cert --password "$svn_pass" --username "$svn_user" "$url"`;
    if ($?) {
	print "\tError $? for svn list.\n";
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
	die "\tError $? for svn checkout $url to $local.\n";
	return undef;
    }
    print "$output\n";
    return 1;
}


sub svn_info {
    my ($url, $svn_pass, $svn_user) = @_;
    my $output = `svn info --non-interactive --no-auth-cache --trust-server-cert --password "$svn_pass" --username "$svn_user" "$url"`;
    if ($?) {
	print "\tError $? for svn info.\n";
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

    print "\t-Get from url $url_path.\n";
    my $retries = 0;
    while ($retries < 3) {
	$request->uri( $url_path );
	my $response = $ua->request($request);
	if ($response->is_success) {
	    $content .= $response->content;
# 	    print $response->decoded_content;
	    last;
	}else {
	    if ($response->status_line eq "404 Not Found") {
		return;
	    } else {
		print Dumper($response->status_line) ."\tfor file $url_path\n" ;
		$retries++;
	    }
	}
    }
    die "Unknown error when retrieving file $url_path.\n" if $retries >= 3;
    my $res = "";
    if ( defined $local_path && $local_path !~ m/^\s*$/i ) {
	write_file("$local_path/$name$suffix", $content);
	$res = "$local_path/$name$suffix";
    } else {
	$res = $content;
    }
    print "\t+Get from url $url_path.\n";
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
# 	    unlink("$key") or die "Could not delete the file $key: ".$!."\n";
	    unlink("$key") or return 1;
	    delete $clean_up->{"$key"};
	}
    }
    foreach my $key (keys %$clean_up) {
	if ($clean_up->{$key} eq "dir") {
	    remove_tree("$key");
	    delete $clean_up->{"$key"};
	} else {
# 	    die "caca $clean_up->{$key} for $key\n";
	    print "caca $clean_up->{$key} for $key\n";
	    return 1;
	}
    }
    return 1 if scalar keys %$clean_up;
    $clean_up = {};
    return 0;
}

sub copy_dir {
    my ($from_dir, $to_dir) = @_;
    opendir my($dh), $from_dir or die "Could not open dir '$from_dir': $!";
    for my $entry (readdir $dh) {
#         next if $entry =~ /$regex/;
        my $source = "$from_dir/$entry";
        my $destination = "$to_dir/$entry";
        if (-d $source) {
	    next if $source =~ "\.?\.";
            mkdir $destination or die "mkdir '$destination' failed: $!" if not -e $destination;
            copy_dir($source, $destination);
        } else {
            copy($source, $destination) or die "copy failed: $source to $destination $!";
        }
    }
    closedir $dh;
    return;
}

sub move_dir {
    my ($src, $trg) = @_;
    die "\tTarget $trg is a file.\n" if (-f $trg);
    makedir("$trg", 1) if (! -e $trg);
    opendir(DIR, "$src") || die("Cannot open directory $src.\n");
    my @files = grep { (!/^\.\.?$/) } readdir(DIR);
    closedir(DIR);
    foreach my $file (@files){
	move("$src/$file", "$trg/$file") or die "Move file $src/$file to $trg failed: $!\n";
    }
    remove_tree("$src") || die "Can't remove dir $src.\n";
}

sub write_file {
    my ($path,$text, $remove) = @_;
    $remove = 0 if not defined $remove;
    my ($name,$dir,$suffix) = fileparse($path, qr/\.[^.]*/);
    add_to_remove("$dir/$name$suffix", "file") if $remove ne 0;
    print "\tWriting file $name$suffix.\t". get_time_diff() ."\n";
    open (FILE, ">$path") or die "at generic write can't open file $path for writing: $!\n";
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
	    if ($file eq '') { print "general error: $message.\n"; }
	    else { print "problem unlinking $file: $message.\n"; }
	}
	die "Can't make dir $dir: $!.\n";
    }
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
    my $doc_file = shift;
    open(FILE, $doc_file) or die "Can't open '$doc_file': $!\n";
    binmode(FILE);
    my $doc_md5 = Digest::MD5->new->addfile(*FILE)->hexdigest;
    close(FILE);
#     my $doc_md5 = "123";
    return $doc_md5;
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
	die "Capitalization: first (first letter is capital and the rest remain the same), small (all letters to lowercase) or all (only first letter is capital, and the rest are lowercase).\n";
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
    die "main $main or ver $ver is not defined.\n" if (! defined $main || ! defined $ver);
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

    die "Main version $main is not correct.\n" if $main !~ m/$regexp_main/i;
#     die "Ver version $ver is not correct.\n" if $ver !~ m/$regexp_ver/i;
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

    die "Main $main_v is not like version $ver_v.\n" if $ver_v !~ m/^$main_v/;

    return $big_ver, $main_v, $ver_v, $ver_fixed, $ver_sp, $ver_id;
}

sub generate_html_file {
    my $doc_file = shift;
    my ($name,$dir,$suffix) = fileparse($doc_file, qr/\.[^.]*/);
    print "\t-Generating html file from $name$suffix.\t". (get_time_diff) ."\n";
    eval {
	local $SIG{ALRM} = sub { die "alarm\n" };
	alarm 46800; # 13 hours
	system("python $real_path/unoconv -l -p 8100 2>&1 /dev/null &") == 0 or die "unoconv failed: $?";
	sleep 2;
	system("python", "$real_path/unoconv", "-f", "html", "$doc_file") == 0 or die "unoconv failed: $?";
	alarm 0;
    };
    my $status = $@;
    if ($status) {
	print "Error: Timed out: $status.\n";
	eval {
	    local $SIG{ALRM} = sub { die "alarm\n" };
	    alarm 46800; # 13 hours
	    system("python $real_path/unoconv -l -p 8100 2>&1 /dev/null &") == 0 or die "unoconv failed: $?";
	    sleep 2;
	    system("/opt/jre1.6.0/bin/java", "-jar", "$real_path/jodconverter-2.2.2/lib/jodconverter-cli-2.2.2.jar", "-f", "html", "$doc_file") == 0 or die "jodconverter failed: $?";
	    alarm 0;
	};
	$status = $@;
	if ($status) {
	    print "Error: Timed out: $status.\n";
	} else {
	    print "\tFinished: $status.\n";
	}
    } else {
	print "\tFinished: $status.\n";
    }


    print "\t+Generating html file from $name$suffix.\t". (get_time_diff) ."\n";
    return $status;
}

sub reset_time {
    $start_time = time();
}

sub array_diff {
    print "-Compute difference and uniqueness.\n";
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
    print "\tdifference done.\n";

    my $arr1_hash = ();
    $arr1_hash->{$_} = 1 foreach (@$arr1);

    foreach my $element (@difference) {
	if (exists $arr1_hash->{$element}) {
	    push @only_in_arr1, $element;
	} else {
	    push @only_in_arr2, $element;
	}
    }
    print "+Compute difference and uniqueness.\n";
    return \@only_in_arr1,  \@only_in_arr2,  \@intersection;
}

sub get_correct_customer{
    my $name = shift;
    $name =~ s/(^\s+)|(\s+$)//g;
    return "" if $name =~ m/^\s*$/;

    return "AFRIPA" if $name eq "Afripa Telecom";
    return "SIW" if $name =~ m/^SI$/i;
    return "VDC" if $name eq "VTI";
    return "TELEFONICA PERU" if $name eq "Telefonica Del Peru" || $name eq "Telefonica - Peru";
    return "Budget Tel" if $name eq "Budgettel";
    return "Telecom-Colombia" if $name eq "colombia" || $name eq "Telecom Kolumbia" || $name eq "Telecom - Colombia";
    return "MSTelcom" if $name eq "MSTelecom";
    return "Mobee" if $name eq "MobeeTel" ||$name =~ m/mobi/i;
    return "CWP" if $name eq "CWPanama" || $name eq "Cable & Wireless" || $name eq "Bell South Panama" || $name eq "BellSouth Panama"
	    || $name eq "Bell South";
    return "alcatel" if $name eq "Vendors: Alcatel" || $name eq "Alcatel / NerDring";
    return "3KInt" if $name eq "3K intl" || $name eq "MIND-3KInt"; #$name eq "MIND-SR 3KInt" ||
    return "H3G Italy" if $name eq "H3G" || $name eq "h3g" || $name eq "H3G - IBM" || $name eq "H3g" || $name eq "H3G Omnitel"
	    || $name eq "H3G Omnitel" || $name eq "H3G Italiano" || $name eq "Italy and HK" || $name eq "H3G-Italy" || $name eq "h3g iatly"
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

return 1;
