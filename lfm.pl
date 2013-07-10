#!/usr/bin/perl -w
#BUGS 
#
# lfm t -s title -> sorts on artist
#
#
package constants;
use constant OUTPUT_LIMIT	=> 14; # lines
use constant WIDTH_ARTIST	=> 43; # chars
use constant WIDTH_SONG		=> 23; 
use constant DEBUG			=> 1;

my $lfm_sk;   
my $lfm_user;
my $lfmrc   = "$ENV{'HOME'}/.mpc/last.fm"; # username:sessionkey
my $apikey  = '1dfdc3a278e6bac5c76442532fcd6a05';
my $secret	= 'a70bafc9e39612700a2c1b61b5e0ab61';
my $service = 'https://ws.audioscrobbler.com/2.0/';
#my $service = 'http://ws.audioscrobbler.com/2.0/';
my $httpTimeout	= 35;
my $terminal_encoding = $ENV{'LANGUAGE'} || $ENV{'LANG'} || 'en_US.iso8859-1';
   $terminal_encoding =~ s/\w*\.//;
#
# FEEL FREE TO EDIT BELOW THIS LINE
#
binmode STDOUT, ":encoding($terminal_encoding)";
use strict;
use warnings;
use v5.10;
use Data::Dumper;
use LWP::UserAgent;
use LWP::Protocol::https;
#use IO::Socket::SSL;
use URI::QueryParam;
#export PERL_LWP_SSL_VERIFY_HOSTNAME=0



sub Whatever::call_api20($);
sub Help::printError($$$);

my $exit_good = 0;
my $exit_bad = 1;
my $exit_pebkac = 2;

if (-e ! $lfmrc) { 
	Help::usage("run get-session_key.sh and set \$lfmrc in lfm.pl"); 
	die "Did you make a session key?"; }

open(CONF, "<$lfmrc") or die "config file? session key? ($lfmrc)";
while (<CONF>) {
	chomp; if (/:/) {
	$lfm_user = $_; $lfm_user =~ s/:.*//; 
	$lfm_sk = $_; $lfm_sk =~ s/.*://;
	}} close(CONF);

if (length($lfm_user)==0 or
	length($lfm_sk)<32) { 
	die "Could not read `user:sessionKey' from $lfmrc."; }

my %args_short;
my %args_sshort; 
my %args_long;

%args_short = (
 '-a'  => {'add'=>'s', 'tag'=>'s' ,              'love'=>'s',                                            }, 
 '-A'  => {            'tag'=>'s'                                                                        },
 '-d'  => {                        'create'=>'s'                                                         }, 
 '-l'  => {'add'=>'i', 'tag'=>'i',               'love'=>'i', 'playlists'=>'i',     'tracks'=>'i'        }, 
 '-n'  => {                        'create'=>'s'                                                         }, 
 '-p'  => {'add'=>'i'                                                                                    }, 
 '-r'  => {            'tag'=>'n',               'love'=>'n', 'playlists'=>'n',     'tracks'=>'n'        }, 
 '-s'  => {                                                   'playlists'=>'{ITt}', 'tracks'=>'{ItA}'    }, 
 '-t'  => {'add'=>'i', 'tag'=>'i',               'love'=>'i'                                             },); %args_sshort = (
 '-ol' => {            'tag'=>'i'                                                                        },
 '-ta' => {            'tag'=>'s'                                                                        }, 
 '-tA' => {            'tag'=>'s'                                                                        },
 '-tt' => {            'tag'=>'s'                                                                        },
 '-ls' => {            'tag'=>'n'                                                                        },); %args_long = (
'--t'  => {'add'=>'s', 'tag'=>'s',               'love'=>'s'                                             },
'--p'  => {'add'=>'s'                                                                                    }, 
);
my %commands = (
	'add'       => { api => 'playlist.addtrack'   , },
	'create'    => { api => 'playlist.create'     , },
	'love'      => { api => 'track.love'          , },
	'playlists' => { api => "user.getplaylists"   , },
	'tracks'    => { api => 'user.getrecenttracks', },
	'tag'       => { mix => 'worktags'            , },
	'help'      => { });
my %commands_short = (
	a => 'add',
	c => 'create',
	l => 'love',
	p => 'playlists',
	t => 'tracks',
	T => 'tag',);
my %argvalues = ( 
	'n' => 'None',
	's' => 'String',
	'i' => 'Number',
	'I' => 'ID',
	't' => 'Track',
	'T' => 'Title',
	'A' => 'Artist'
);

my @all_possible_args = (keys %args_long, keys %args_sshort, keys %args_short);
my @all_singlechar_args = (keys %args_long, keys %args_short);
my %cliargs; #<- sub parse_options
my $command; #<- sub determined_mode
my $invalid='~'; #<- sub option_type_in_mode.
                 #   means illegal option value for mode (ie. add -t zebra, 
				 #   because -t takes an int).

sub determined_mode {
	for (my $i=0; $i<scalar @ARGV; $i++) {
		if (grep { $_ eq $ARGV[$i]} (keys %commands, keys %commands_short)) {
			if  ($i eq 0) { return splice @ARGV, $i, 1; }
			return $ARGV[$i] }}
}

sub option_type_in_mode($$){
	my ($opt, $mode) = @_;
	my (%argsa, $type);
	@argsa{keys %args_short} = values %args_short;
	@argsa{keys %args_sshort} = values %args_sshort;
	@argsa{keys %args_long} = values %args_long;
	$mode = $commands_short{$mode} || $mode;
	if (defined($argsa{$opt}{$mode})) { # check if opion is defind in current mode
		return $argsa{$opt}{$mode}; }
	return $invalid;
}

sub parse_options() {
	my %options = ();
	my ($a, $v, $optim, $optval, $applicable);
	my $re_single = sprintf '^(%s)(.*)$', join('|', @all_singlechar_args);
	my $re_double = sprintf '^(%s)(.*)$', join('|', (keys %args_sshort) );

	# set minus set : @all_possible_args - @all_singlechar_args
	# my %singlechar = map { $_ => 1} @all_singlechar_args;
    # my @all_doublechar_args = grep { not $singlechar{$_} } @all_possible_args;
	# my $re_double = sprintf '^(%s)(.*)$', join('|', @all_doublechar_args );
	
	while (scalar @ARGV > 0) {
		$a = splice @ARGV, 0, 1;
		$applicable = option_type_in_mode($a, $command) ne $invalid;

		# -a Nick, -t Wepping\ Song -p 'Rock & Roll'
		if (grep { $_ eq $a} @all_possible_args and  $applicable) {
			$v = splice @ARGV, 0, 1;
		    $v = $v || $invalid;
			#printf "# %s -> %s: %s\n", $a, $optim, $v;

			$optim = option_type_in_mode($a, $command);
			if ($optim eq 'n') {
				splice @ARGV, 0, 0, ($v) unless $v eq $invalid;
				$options{$a} = [$optim => 0xf055];

			}
			elsif (not grep { $_ eq $v} ($invalid, @all_possible_args)) {
				$options{$a} = [$optim => $v];

			}
			elsif (defined($argvalues{$optim}) and  $argvalues{$optim} eq 'None') {
				$options{$a} = [$optim => 0xf055];

			}
			else {
				# split {ItA} into "it|track|artist"
				if ($optim =~ /^{(.*)}$/) {
					my %optlist = map { $_ => $argvalues{$_} } split(//, $1);
					$optim = join('|', values %optlist ); }
				else {
					$optim = $argvalues{$optim}; }
				#exit 1;
				Help::usage('Wrong parameter', sprintf (
					"The option %s takes a value of type '%s' in %s mode.\n",
					$a, $optim, $command),
					$exit_pebkac);
			}

		# -aNick, -t'Weeping Song', -pRock\ "& Roll"
		} elsif (
				(($a =~ /$re_double/) or
				 ($a =~ /$re_single/))
				and option_type_in_mode($1, $command) ne $invalid) {
			($a, $v) = ($1, $2);

			$optim = option_type_in_mode($a, $command);

			if ($optim eq 'n') {
				splice @ARGV, 0, 0, ($v) unless $v eq $invalid;
				$options{$a} = [$optim => 0xf055];
			} else {
				$options{$a} = [$optim => $v];
			}
			#printf "# %3s -> %s: %s\n", $a, option_type_in_mode($a, $command), $v;

		} elsif (grep { $_ eq $a} @all_possible_args) {
			Help::usage('Wrong parameter', 
				sprintf ("The command '%s' does not take the option -- '%s'\n", $command, $a), 
				$exit_pebkac);
		} else {
			#printf "'%s' applicable in '%s': >%s<\n", $a, $applicable, $command;
			Help::usage('Wrong parameter', sprintf ("Illegal option -- '%s'\n", $a),
				$exit_pebkac);
		}
	}
	return %options;
}


$command = determined_mode(@ARGV);
$command = $commands_short{$command} || $command || '<command>';
#
# Check input
#
Help::usage("Invalid command.",
	"$command should be one of:\n  @{ [sort (keys %commands, keys %commands_short) ] }", $exit_bad)
	unless (grep {/^$command$/} (keys %commands, keys %commands_short));

%cliargs = parse_options();

#printf "# command: %s; (%s)\n", $command, join(", ", @ARGV);


# assert value type
my %givenArgs;
while ((my $flag, my $value) = each (%cliargs)){
	my $valueType = @$value[0];
	my $parameter = @$value[1];
	#printf "got %3s (%s): %-40s \n", $flag, $valueType, $parameter;

	if	($valueType eq 'i') {
	Help::printError('Wrong parameter.', "$command $flag n must be an integer (tID)", $exit_pebkac)
	unless ($parameter =~ m/^\d+$/); 

		$givenArgs{$command}{$flag} = int $parameter;

	} else {

		$givenArgs{$command}{$flag} = $parameter; 
	}
}


my %OPT = ();
$OPT{sk} 			= $lfm_sk;
$OPT{lfm_user}		= $lfm_user;
$OPT{mix_method}	= $commands{$command}{mix}	|| undef;
$OPT{api_method}	= $commands{$command}{api}	|| undef;
$OPT{limit}			= $cliargs{'-l'}[1] || OUTPUT_LIMIT;
$OPT{reverse} 		= $cliargs{'-r'}[1] || 0;
$OPT{pid}			= $cliargs{'-p'}[1] || 0;
$OPT{playlist}		= $cliargs{'--p'}[1]|| "";
$OPT{tid}			= $cliargs{'-t'}[1] || 0;
$OPT{artist}		= $cliargs{'-a'}[1] || "";
$OPT{album}			= $cliargs{'-A'}[1] || "";
$OPT{track}			= $cliargs{'--t'}[1]|| "";
$OPT{name}			= $cliargs{'-n'}[1] || "";
$OPT{description}	= $cliargs{'-d'}[1] || "";
$OPT{order_by}		= $cliargs{'-s'}[1] || "";
$OPT{output_limit}	= $cliargs{'-ol'}|| 20; # max 100 tags
$OPT{tag_artist}	= $cliargs{'-ta'}|| "";
$OPT{tag_album}		= $cliargs{'-tA'}|| "";
$OPT{tag_track}		= $cliargs{'-tt'}|| "";
#
# Call the API
#
my	$ua = LWP::UserAgent->new(
		keep_alive => undef, # max connections, undef = unlimited
	);
	#$ua->show_progress(1);
	$ua->timeout($httpTimeout);
	$ua->ssl_opts(verify_hostname => 0);
	#$ua->agent('lfm.pl 0.0.2');
	#$ua->conn_cache( $cache_obj ) #  LWP::ConnCache
	#$ua->conn_cache( LWP::ConnCache->new );

	#conn_cache              undef
	#keep_alive 
	#verify_hostname
	#say Dumper($ua);
#call_api20(\%OPT);
#exit -1;
my $lfm = Last->new( \%OPT );
   $lfm->call();
#print "A  A A A \n";
#exit -1;


# new api object

package Last;
use Encode qw(encode_utf8);
use Digest::MD5 qw(md5_hex);
use List::Util qw(min max);
use Data::Dumper;
use XML::Simple;
use Carp;
our $_____hold_it;
our $AUTOLOAD;
my %last_fields = (
	options => {},
	signed_methods => undef,
	peers => undef,
);

sub new {
	my $class = shift;
	my $opts = shift;
	my $self = {_permitted => \%last_fields, %last_fields};
	$self->{options} = $opts;
	$self->{signed_methods} = [
		'track.love', 
		'track.unlove', 
		'artist.addtags',
		'album.addtags',
		'track.addtags',
		'artist.gettags',
		'album.gettags',
		'track.gettags',
		'artist.removetag',
		'album.removetag',
		'track.removetag',
		'playlist.create',
		'playlist.addtrack'
	];
	bless ($self, $class);
	return $self;
};
sub DESTROY { 1; }
sub AUTOLOAD {
	my $self = shift;
	my $type = ref($self) or croak "$self is not an object.";
	my $name = $AUTOLOAD;
	   $name =~ s/.*://;
	unless (ref $self eq 'HASH') { confess sprintf 
		"%s\n%s",
		"Object called improperly. \$self = $self",
		"Offender:\n\t$AUTOLOAD"; 
}
	#unless (ref $self->{_permitted} eq 'HASH') { say "BAD NAME 1 : _permitted"; }
	#unless (ref $self->{_permitted}->{$name} eq 'HASH') { say "BAD NAME 2 : $name"; }
	unless (exists $self->{_permitted}->{$name}) {
		croak "Undefined field: ${type}->${name}"; }
	if (@_) { return $self->{$name} = shift; }
	else { 
			return $self->{$name}; }
};
sub call {
	my $self = shift;
	my %doCall = (
		'user.getplaylists'     => \&user_getplaylists,
		'user.getrecenttracks'  => \&user_getrecenttracks,
		'track.love'            => \&track_love,
		'worktags'              => \&worktags,
	);
	my $method = $self->{options}->{api_method} || $self->{options}->{mix_method} ;

	printf "calling: %s\n", $method;
	&{ $doCall{$method} }(  $self ); 
	print "called.\n";
	return 1;
	## map -t n to an artist, album and a track

};
sub ask_in_unicode_and_get_response {
	my $self = shift;
	my $servargs = shift;
	my $expected_encoding = shift; # i.e. the server wants unicode
	my $response;
	my %unicode_param = ();
	#say "sub ask_in_unicode_and_get_response";
	#say Dumper($servargs);
	my $audioscrobbler	= URI->new($service);
	if (ref $servargs ne 'HASH') {
		Help::printError('Bug.',
			sprintf(": needs more hash reference. (%s)", ref $self),
			$exit_bad);
	}
	while ((my $k,my $v)=each %$servargs){ 
		if ($expected_encoding =~ m/utf\-?8/i){ 
			#skip;
		} else {
			$k = encode_utf8($k);
			$v = encode_utf8($v);
		}
		$unicode_param{$k} = $v;
		$audioscrobbler->query_param($k, $v);
	} 
	my	$signature	 = "";
	if ($servargs->{'sk'}) {
		foreach my $key (sort keys %unicode_param) {
			my $val = $unicode_param{$key};
			$signature .= $key.$val;
		}
		$signature .= $secret; 
		$signature = md5_hex($signature);
		$audioscrobbler->query_param('api_sig', $signature);
		$servargs->{api_sig} = $signature;

		$response = $ua->post($audioscrobbler);
		$audioscrobbler->query_param('sk', '');
	} else {
		$response = $ua->post($audioscrobbler); # use get?
	}
	#say "sub ask_in_unicode_and_get_response ? ";
	unless ($response->is_success) {
		if ($response->code != 200) {
			#say Dumper($response); 
			#say Dumper($audioscrobbler);
			#say Dumper(%servargs);
			my $_uri = $response->request->{_uri} =~ s/([&\?][a-zA-Z_]+=)/\n $1/g;
			say "response != 200;\n" . $_uri;
		}

		if ($response->decoded_content){
			use XML::Simple;
			my $xs = XML::Simple->new();
			my $error = $xs->xml_in($response->decoded_content);
			Help::printWarning($error->{error}{content});
		} else {
			say $response->_content;
		}
		Help::printError('Last.fm: oops', "(".$servargs->{method}."): ".$response->status_line , $exit_bad);
	} 
	#say "sub ask_in_unicode_and_get_response Yes ";
	return $response;
}

# forward http-parameters to encoder > sender > parser
# pre-fetch any data to fill missing parameters
sub get_xml_api20 {      die sprintf "Recursion Fail? (calls%d)" , $_____hold_it
		              unless (our $_____hold_it ++) < 21;
	my $self = shift;
	my $servargs = shift; # %
	my $xmlargs	= shift;  # %
	my $recursive = shift || 0;
	my $opt	= $self->{options}; # %
	my $method 	= $servargs->{method} || $self->{options}->{api_method};
	$servargs->{api_key} = $apikey;
	
	# tID -> artist + title
	if ($opt->{tid} > 0 and $recursive <= 1) {
		my $xml_t = $self->user_getrecenttracks_xml(++ $recursive);
		my $tracks = $xml_t->{recenttracks}{track} ;
		my $idlist_t = Whatever::mapTrackIds($tracks);
		my $idx = 0;
		while (((my $aidx, my $lsid) = each %$idlist_t) && ! $idx){
			if ($opt->{tid} == $lsid) { $idx = $aidx; }
		}
		$servargs->{artist}	= $tracks->[$idx]->{artist}{content};
		$servargs->{album}	= $tracks->[$idx]->{album}{content} || "";
		$servargs->{track}	= $tracks->[$idx]->{name};
	} else {
		$servargs->{artist}	= $opt->{artist};
		$servargs->{album}	= $opt->{album};
		$servargs->{track}	= $opt->{track};
	}

	if (grep {/$method/} ( @{ $self->{signed_methods}})){ 
		$servargs->{sk} = $lfm_sk; }

	my $response = $self->ask_in_unicode_and_get_response($servargs, $terminal_encoding);

	if ($response->is_success) {
		# save output $response->decoded_content;
		my $xs = XML::Simple->new(%{$xmlargs});
		my $moo = $xs->xml_in($response->decoded_content);
		return $moo;
	} else {
		say Dumper($response);
	}
	return -1;
}

sub user_getplaylists_xml {
	my $self = shift;
	my %servargs = (
		method => $commands{playlists}{api},
		method => $OPT{page} || 1,
		page => $OPT{page} || 1,
		user => $OPT{user} || $lfm_user,
		#limit => $OPT{limit},
		#$servargs{from} = `epoch`;
		#$servargs{to} = `epoch`;
	);
	my %xmlargs = (forcearray => 0);
	return $self->get_xml_api20(\%servargs, \%xmlargs );
}
	
sub user_getplaylists { # elsif ($method eq "user.getplaylists") {
	my $self = shift;
	my $xml 	= $self->user_getplaylists_xml();
	my $pls_ref	= $xml->{playlists}->{playlist};
	my %pls		= %{ $pls_ref };
	my $idlist  = Whatever::mapPlaylistIds( $pls_ref);
	my $format	= "% 6s % 3s  %s\n";
	my $sort_sub;
	if 		($OPT{order_by} eq "id"    ){ $sort_sub = \&{ Whatever::sortPlaylistById } }  # todo case insensitive -s ID/id
	elsif	($OPT{order_by} eq "track" ){ $sort_sub = \&{ Whatever::sortPlaylistByTrack } }
	else {                                $sort_sub = \&{ Whatever::sortPlaylistByTitle } }
		printf $format, "len", "pID", "Playlist" ; 
	foreach my $id ( $sort_sub->( $pls_ref, $OPT{reverse})) { 
		printf $format, $pls{$id}{size}, $idlist->{$id}, $pls{$id}{title}; 
	}
	return $exit_good;
};

sub user_getrecenttracks_xml {
	my $self = shift;
	my $recursive = shift;
	#say "grt $recursive";
	if (++$_____hold_it > 20) { die "user_getrecenttracks_xml, $_____hold_it calls"; return};

	my $limit = $self->{options}->{tid};
	   $limit = $self->{options}->{limit} unless $limit > 0;
	my %servargs = (
		method => 'user.getrecenttracks',
		limit => $limit,
		page => $self->{options}->{page} || 1,
		user => $self->{options}->{user} || $lfm_user,
		#$servargs{from} = `epoch`;
		#$servargs{to} = `epoch`;
	);
	my %xmlargs = (keyattr => {}, forcearray => 0);
	my $got = $self->get_xml_api20(\%servargs, \%xmlargs, $recursive);
	return $got;
}

sub user_getrecenttracks {
	my $self = shift;
	my $width_artist = 0;
	my $width_track = 0;
	my $width_id = 2 +(length $OPT{'limit'});
	my $xml	= $self->user_getrecenttracks_xml();
	my $tracks = $xml->{recenttracks}{track} ;
	my @tracks = @{ $tracks };
	my $idlist = Whatever::mapTrackIds($tracks);
	my        $order = $self->{options}->{order_by};
	my                                 $sort_sub = \&{ Whatever::sortTracksByDate };
	if (      $order =~ m/title/i ) {  $sort_sub = \&{ Whatever::sortTracksByTitle } 
	} elsif ( $order =~ m/artist/i ) { $sort_sub = \&{ Whatever::sortTracksByArtist } }
	my @sorted	= $sort_sub->($tracks, $OPT{reverse});
	#find longest name or title
	foreach (@tracks){
		$width_artist = max(length($_->{artist}->{content}), $width_artist);
		$width_track = max(length($_->{name}), $width_track); }
	$width_artist = min(constants::WIDTH_ARTIST, $width_artist);
	$width_track = min(constants::WIDTH_SONG, $width_track);
	$width_track += 4-($width_id);
	my $format =
	"% ".$width_id."s %02s:%02s % ".$width_artist."s - %- ".$width_track."s\n";
	printf STDERR $format, "tID", "hh", "mm", "Artist", "Track";
	foreach (@sorted){
		my $trk	= $tracks[$_];
		my $epoch = $trk->{date}->{uts} || time;
		my $name = $trk->{name};
		my $artist = $trk->{artist}->{content};
		my ($min,$hour) = (localtime($epoch))[1,2] ;
		printf $format, $idlist->{$_}, $hour, $min, $artist, $name;
	}
	return $exit_good;
}
#our $_____hold_it;
sub track_love {
	my $self = shift;
	my $function;
	if ($self->{options}{reverse} == 0xf055) {
		$function = 'track.unlove'; } else {
		$function = $self->{options}{api_method};} 
	my $xml = $self->get_xml_api20({method => $function,
                                    track => $self->{options}{track},
                                    artist => $self->{options}{artist} },
									{}, 1); # xmlargs and anti-recurse
	return $exit_good;
}

sub playlist_create {
	my $self = shift;
	my %servargs = (
		method => 'playlist.create',
		name => $self->{options}->{name},
		descriptions => $self->{options}->{descriptions},
	);
	return $self->get_xml_api20(\%servargs, {});
}

sub printTags {
	my $self = shift;
	my $servargs = shift;
	my $method = shift;
	#my %OPT = %{$_[3]};
	my $aat_key = ((split /\./, $method)[0]);
	my $aat_val	= $servargs->{$aat_key};

	my @ordered = ();
	my %tags = ();
	my $xml	= ();
	my $max	= 0;
	my $line = 0;
	my $onetoptag =	0;
	my $appliedtags = 0;

	$servargs->{method} = $method;
	#$xml		= getXml_api20(\%opt_toptags);
	$xml		= $self->get_xml_api20( $servargs );

	if ($method =~ m/gettoptags$/){
		printf "%s (%s tags)\n", $aat_val, $aat_key; 
	}

	if ($xml != -1) {
		if      (defined $xml->{toptags}{tag}) {
			%tags 	= %{ $xml->{toptags}{tag}};
		} elsif (defined $xml->{tags}{tag}) {
			%tags 	= %{ $xml->{tags}{tag}};
			$appliedtags = 1;
			#print Dumper ($xml);

		} else {
			if ($command eq 'gettoptags'){
				print "No tags";
			}
		}

		my $onetoptag =	exists $tags{count} && 
		 				exists $tags{name} && 
		 				exists $tags{url};

		if ($onetoptag){
			$ordered[0] = $tags{name};
		} elsif ($appliedtags) {
			print "    Saved:\n";
			@ordered = sort keys %tags;
			#say Dumper( \@ordered );
			#say $ordered[0];
			#say $ordered[1];
			#say $ordered[2];
		} else {
			@ordered = sort { $tags{$b}{count} <=> $tags{$a}{count} } keys %tags;
		}
		$max = min($self->{options}->{output_limit}, scalar (@ordered));
		$line = '    ';
		my $lines = '';
		for (my $i=0; $i < $max; $i++){
			my $otag = $ordered[$i];
			#printf "%d -- %d $otag \n", $i+1, $max;
			my $ll = length ($line . $otag);
			if ($ll <= 80) {
				$line .= "$otag, ";
			} else {
				$lines .= "$line\n";
				$line = '    ';
			}
			if (($i+1) == $max) { # flush
				$lines .= "$line\n";
				$line = '    ';
			}
		}
		$lines =~ s/, ?$/\n/;
		print $lines unless $lines eq '';
	} else {
		print "No tags";
	}
	#print "\n";
	if ($command eq 'gettags' && scalar @ordered >= 1){
	#print "\n";
	}
}

sub worktags { # add, remove, list
	my $self = shift;
	#my $method = $self->{options}->{api_method};

	my %servargs = (
		#method => $self->{options}->{api_method},
		#tag_artist => $self->{options}->{tag_artist};
		#tag_album => $self->{options}->{tag_album};
		#tag_track => $self->{options}->{tag_track};
		# artist => $self->{options}->{artist},
		# album => $self->{options}->{album},
		# track => $self->{options}->{track},
		autocorrect => 1,
);

	my $method;
	my $remove = $servargs{reverse} || '';
	my $add = '';
	my $art = $servargs{tag_artist} || '';
	my $alb = $servargs{tag_album} || '';
	my $trk = $servargs{tag_track} || '';
	my $A = $self->{options}->{artist} || '';
	my $a = $self->{options}->{album} || '';
	my $t = $self->{options}->{track} || '';
	my $tid = $self->{options}->{tid} || 0;


	if ($remove and $art) {
		$servargs{method} = "artist.removetag"; 
		$servargs{artist} = $self->{options}->{artist};
		$servargs{tag} = $art;
	} elsif ($art) {
		$servargs{method} = "artist.addtags"; 
		$servargs{tags}	= $art;
	}

	if ($remove and $alb) {
		$servargs{method} = "album.removetag"; 
		$servargs{tag} = $alb;
	} elsif ($alb) {
		$servargs{method} = "album.addtags"; 
		$servargs{tags} = $alb;
	}

	if ($remove and $trk) {
		$servargs{method} = "track.removetag"; 
		$servargs{tag} = $trk;
	} elsif ($trk) {
		$servargs{method} = "track.addtags"; 
		$servargs{tags}	= $trk;
	}

	if ($A) { $servargs{artist} = $self->{options}->{artist};}
	if ($a) { $servargs{album} = $self->{options}->{album};}
	if ($t) { $servargs{track} = $self->{options}->{track};}

	if ($remove) {
		# api {artist,album,track}.removetag takes only one tag at a time
		foreach my $aat (qw(tag_artist tag_album tag_track)) {
			foreach my $tag (split ',', $self->{options}->{$aat} ) {
				$servargs{$aat} = $tag;
				printf 'removing %s for %s', $tag, $A.'-'.$a.'-'.$t;
				#say Dumper(\%servargs);
				#call_api20(\%OPT_TEMP);
				#return $self->get_xml_api20(\%servargs, {});
			}
		}
		return 1;
	} elsif ($add) {
		$method = $servargs{method} || '';
		     if ($method eq "artist.addtags") { 
		} elsif ($method eq  "album.addtags") { 
		} elsif ($method eq  "track.addtags") { 
		} elsif ($method eq "artist.removetag") { 
		} elsif ($method eq  "album.removetag") { 
		} elsif ($method eq  "track.removetag") { 
		} else {
			Help::printError('Not Implemented', (caller(0))[3].": Routine not defined for $method", $exit_bad); 
			# 	exit 1;
		}
	}

	#if ($A.$a.$t eq '') { }

	if ($A or $tid){ $self->printTags(\%servargs, 'artist.gettoptags' ); }
	if ($A or $tid){ $self->printTags(\%servargs, 'artist.gettoptags' ); }
	if ($A or $tid){ $self->printTags(\%servargs, 'artist.gettags'    ); }
	if ($a or $tid){ $self->printTags(\%servargs, 'album.gettoptags'  ); }
	if ($a or $tid){ $self->printTags(\%servargs, 'album.gettags'     ); }
	if ($t or $tid){ $self->printTags(\%servargs, 'track.gettoptags'  ); }
	if ($t or $tid){ $self->printTags(\%servargs, 'track.gettags'     ); }

	# input validation
	if ($A.$a.$t eq '' and not $tid) { Help::usage('Not enough arguments.', "I need -artist (and -Album and/or --track)"); }

	#say "worktags";
	#say Dumper(\%servargs);
}

	
	#call_api20(\%OPT); 



1;

package Whatever;
sub min (@) { reduce { $a < $b ? $a : $b } @_ }
sub max (@) { reduce { $a > $b ? $a : $b } @_ }

# Submit a REST query
#
#	elsif ($method eq "artist.gettoptags") {
#		$servargs{artist} = $OPT{'artist'};
#		$servargs{autocorrect} = 1;
#		#$mbid	= $OPT{mbid}
#	}
#
#	elsif ($method eq "album.gettoptags") {
#		$servargs{artist} = $OPT{'artist'};
#		$servargs{album} = $OPT{'album'};
#		$servargs{autocorrect} = 1;
#		#$mbid = $OPT{mbid}
#
#	}
#	elsif ($method eq "track.gettoptags") {
#		$servargs{artist} = $OPT{'artist'};
#		$servargs{track} = $OPT{'track'};
#		$servargs{autocorrect} = 1;
#		#$mbid = $OPT{mbid}
#	}
#
#	elsif ($method eq "artist.gettags") {
#		$servargs{artist} = $OPT{'artist'};
#		$servargs{autocorrect} = 1;
#		#$mbid = $OPT{mbid}
#	}
#
#	elsif ($method eq "album.gettags") {
#		$servargs{artist} = $OPT{'artist'};
#		$servargs{album} = $OPT{'album'};
#		$servargs{autocorrect} = 1;
#		#$mbid = $OPT{mbid}
#
#	}
#	elsif ($method eq "track.gettags") {
#		$servargs{artist} = $OPT{'artist'};
#		$servargs{track} = $OPT{'track'};
#		$servargs{autocorrect} = 1;
#		#$mbid = $OPT{mbid}
#	} else {
#		printError('Missing Arguments', "Routine for fetching xml ($method) is not defined ", $exit_pebkac);
#	}
#
#	my $response = getResponse(\%servargs, 'utf8');
#	#print Dumper($response->decoded_content);
#	if ($response->is_success) {
#		#print Dumper( XMLin(($response->decoded_content, @xmlargs)) );
#		return XMLin(($response->decoded_content, @xmlargs));
#	} else {
#		say Dumper($response);
#	}
#	return -1;
#}
# -------------------------

# oldcall
sub call_api20($){
	my %opt_toptags = (
		artist		=> $OPT{artist},
		album		=> $OPT{album},
		track		=> $OPT{track},
	);

	my $method;
	my %servargs;
	my $call = $servargs{method};


	if ($call eq "playlist.addtrack") {
		# map --p or -p to a playlist id
		#my $xml_p	= getXml_api20(\%opt_playlists);    # todo: cache this until a new list is added
		my $xml_p = $lfm->user_getplaylists();
		my $pls_ref	= $xml_p->{playlists}->{playlist};
		my $idlist_p= mapPlaylistIds($pls_ref);
		my $lfm_plid= 0;

		if ($OPT{pid} !=0) {
			while ( ((my $lfmid, my $lsid) = each %$idlist_p) && ! $lfm_plid){
				if ($OPT{pid} == $lsid) {
					$lfm_plid = $lfmid;
					$OPT{playlist} = $pls_ref->{$lfmid}->{title};
				}
			}
		} elsif ($OPT{playlist} ne "") {
			my $andexpr = "";
			my %found =();
			foreach (split /\s+/, $OPT{playlist} ){
				$andexpr = $andexpr . "/$_/ && "; 
			} 	$andexpr =~ s/&&\s?\z//;
				$andexpr =~ s,^$,/.*/,;

			foreach my $pls_id (keys %$pls_ref){
				my $pls_name = $pls_ref->{$pls_id}->{title};
				if (grep {eval $andexpr} $pls_name){
					$found{$idlist_p->{$pls_id}} = $pls_name;
					$lfm_plid = $pls_id;
					$OPT{playlist} = $pls_name;
				}
			}
			if ((scalar keys %found) >= 2 ){
				print STDERR "add $OPT{artist} - $OPT{track}\nto which playlist?\n";
				my $format = "% 4s %s\n";
					printf STDERR $format, "id", "name";
				foreach (sort {$found{$a} cmp $found{$b} } keys %found){ 
					printf $format, $_, $found{$_}; }
				return 1;
			 }
		} 

		printError("Last.fm:", "No such playlist", $exit_pebkac) if (! $lfm_plid );
		printWarning("Bad artist name") if ($servargs{artist} =~ m/^$/ );
		printWarning("Bad track name") if ($servargs{track} =~ m/^$/ );

		$servargs{playlistID}	= $lfm_plid;



		}


		# } elsif ($call eq "artist.addtags") { $servargs{tags}	= $OPT{tag_artist};
		# } elsif ($call eq  "album.addtags") { $servargs{tags}	= $OPT{tag_album};
		# } elsif ($call eq  "track.addtags") { $servargs{tags}	= $OPT{tag_track};
		# } elsif ($call eq "artist.removetag") { $servargs{tag}	= $OPT{tag_artist};
		# } elsif ($call eq  "album.removetag") { $servargs{tag}	= $OPT{tag_album};
		# } elsif ($call eq  "track.removetag") { $servargs{tag}	= $OPT{tag_track}; 
		# } else {
		# 	printError('Not Implemented', (caller(0))[3].": Routine not defined for $OPT{api_method}", $exit_bad); 
		# 	exit 1;
		# }
 
	my $response = getResponse(\%servargs, $terminal_encoding);

	my $confirmation = "";
	if ($response->is_success) {
		$call = $servargs{method};
		if    ($call eq "track.love") { $confirmation = "loved song: $servargs{artist} - $servargs{track}"; }
		elsif ($call eq "track.unlove") { $confirmation = "unloved song: $servargs{artist} - $servargs{track}"; }
		elsif ($call eq "playlist.create") { $confirmation = "created playlist: $OPT{name}\n\t$OPT{description}"; } 
		elsif ($call eq "playlist.addtrack") { $confirmation = "added $OPT{artist} - $OPT{track} to $OPT{playlist}\n"; } 
		elsif ($call eq "artist.addtags") { $confirmation = "tagged $OPT{artist} with $OPT{tag_artist}\n"; } 
		elsif ($call eq "album.addtags") { $confirmation = "tagged $OPT{album} with $OPT{tag_album}\n"; } 
		elsif ($call eq "track.addtags") { $confirmation = "tagged $OPT{track} with $OPT{tag_track}\n"; } 
		print "$confirmation\n";
		return 0;
	}	
}

#
# Helpers 
#

sub mapTrackIds {

	my $tracks = $_[0];
	my $reverse= $_[1];

	my @sorted = sortTracksByDate($tracks);
	my %idlist = ();
	my $len = @sorted;
	my $backwards = 0;

	# make shortcuts
	foreach (@sorted){
		if ($reverse){
			$idlist{$_} = ++$backwards;
		} else {
			$idlist{$_} = $len--;
		}
	}
	return \%idlist;

}
sub mapPlaylistIds {
	use Data::Dumper;

	my $xmlref	= $_[0];
	my $reverse = 1;
	my $len		= keys %{ $xmlref };
	my %idlist	= ();

	foreach my $id ( sortPlaylistById( $xmlref, $reverse)) { 
		$idlist{$id} = $len--;
	}
	return \%idlist
}

sub sortPlaylistByTitle($$){
	my %xml		= %{ $_[0] };
	my $reverse	= $_[1];
	my @ret = sort { 
		lc($xml{$a}{title}) 
		cmp 
		lc($xml{$b}{title}) 
	} keys %xml;
	return reverse @ret if ($reverse);
	return @ret;
}
sub sortPlaylistByTrack($$){
	my %xml		= %{ $_[0] };
	my $reverse	= $_[1];
	my @ret = sort { 
		my $left  = $xml{$a}{size} || 0;
		my $right = $xml{$b}{size} || 0;
		$left <=> $right
	} keys %xml;
	return reverse @ret if ($reverse);
	return @ret;
}
sub sortPlaylistById($$){
	my %xml		= %{$_[0]};
	my $reverse	= $_[1];
	my @ret = sort keys %xml;
	return reverse @ret if ($reverse);
	return @ret;
}
sub sortTracksByDate($$) {
	my @in		= @{$_[0]};
	my $reverse = $_[1];
	my $now = time;
	my @ret = sort { 
		my $left = $in[$a]->{date}->{uts} || $now;
		my $right= $in[$b]->{date}->{uts} || $now;
		$left <=> $right 
	} keys @in;
	return reverse @ret if ($reverse);
	return @ret;
}

sub sortTracksByArtist($$) {
	my @in 		= @{$_[0]};
	my $reverse	= $_[1];
	my @ret = sort { 
		my $left  = lc($in[$a]->{artist}{content}.$in[$a]->{name});
		my $right = lc($in[$b]->{artist}{content}.$in[$b]->{name});
		$left cmp $right 
	} keys @in;
	return reverse @ret if ($reverse);
	return @ret;
}

sub sortTracksByTitle($$) {
	my @in		= @{$_[0]};
	my $reverse	= $_[1];
	my @ret = sort { 
		my $left = lc($in[$a]->{name});
		my $right= lc($in[$b]->{name});
		$left cmp $right 
	} keys @in;
	return reverse @ret if ($reverse);
	return @ret;
}

sub utf8_value($$){
	if (! defined $_[0] ){ return undef; }
	my $incoding 	= $_[1];
	my $out 		= $_[0];
	my $octets = encode($incoding, $out);
	my $string = decode('utf-8', $octets);
	return $string;
}


package Help;
use Carp;
sub printError($$$) {
	(my $context, my $error, my $code) = @_;
	$context = $context || undef;
	$error = $error || undef;
	$code = $code || 1;
	if (not defined $context or not defined $error) {
		confess "printError needs 2 args.";
	}
	printf "%s\n  %s\n", $context, $error ;
	exit $code;
}
sub printWarning($) { 
	printError('Last.fm:', $_[0], 0);
}
sub usage {
	(my $context, my $error, my $code) = @_;

	# todo: allow songs be named [0-9]*
	my $help =<< 'EOH'
	.usage: $0 <command> [options]
	. where command is one of 
	.   a dd  .  .  .  .  append song to playlist
	.   c reate  .  .  .  new playlist
	.   l ove    .  .  .  ❥  a track 
	.   p laylists  .  .  show playlists
	.   t racks  .  .  .  show recent scrobbles
	.   T ag  .  .  .  .  add or list tags
	.
	. applicability of options:
	.   create  .  -d DESCRIPTION -n NAME
	.   add  .  .  { -t tID | --t TITLE -a NAME} { --p NAME | -p pID }
	.   love .  .  { -t tID | --t TITLE -a NAME} [ -r (unlove)  ]    
	.   playlists  -s {id title tracks}
	.   tracks  .  -s {id title artist}
	.   tag  .  .  -a artist -A album -t tID --t track -ls
	. general options
	.   -r               reverse sort order (or unlove)
	.   -l num           limit output to num lines
	.   -s column        order output on column
EOH
	;

#  '-ol' => {            'tag'=>'i'                                                                        },
#  '-ta' => {            'tag'=>'s'                                                                        }, 
#  '-tA' => {            'tag'=>'s'                                                                        },
#  '-tt' => {            'tag'=>'s'                                                                        },
#  '-ls' => {            'tag'=>'n'                                                                        },
#  ); my %args_long = (
# '--t'  => {'add'=>'s',      'tag'=>'s',         'love'=>'s'                                              },
# '--p'  => {'add'=>'s'                                                                                    }, 

	$help =~ s/^\t+\.//gm;
	my $_lfm  = (split '/',$0)[-1];
	$help =~ s/\$0/$_lfm/;
	print STDERR '[!]', $0, "\n";
	print STDERR "$help\n";
	Help::printError($context, $error, $code);
}
