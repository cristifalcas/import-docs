package WikiSQLite;

use warnings;
use strict;

use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Log::Log4perl qw(:easy);

sub new {
    my $class = shift;
    my $self = {};
    bless($self, $class);
    return $self;
}

$dbh_mysql = DBI->connect("DBI:mysql:database=$wikidb_name;host=$wikidb_server", "$wikidb_user", "$wikidb_pass");
print "$sc_table";
my $sth_mysql = $dbh_mysql->prepare("CREATE TABLE IF NOT EXISTS $sc_table (
SC_ID VARCHAR( 255 ) NOT NULL ,
FIXVERSION VARCHAR( 255 ) ,
BUILDVERSION VARCHAR( 255 ) ,
VERSION VARCHAR( 255 ) ,
PRODVERSION VARCHAR( 255 ) ,
PRIMARY KEY ( SC_ID ))");
$sth_mysql->execute();
$sth_mysql->finish(); 


 my $sth_mysql = $dbh_mysql->prepare("REPLACE INTO $sc_table VALUES ('$change_id', '@$info[$index->{'fixversion'}]', '@$info[$index->{'buildversion'}]', ' @$info[$index->{'version'}]', '@$info[$index->{'prodversion'}]')");
    $sth_mysql->execute();
    $sth_mysql->finish(); 

return 1;
