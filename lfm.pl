#!/usr/bin/perl -w

use constant OUTPUT_LIMIT	=> 14; # lines
use constant WIDTH_ARTIST	=> 43; # chars
use constant WIDTH_SONG		=> 23; 
use constant DEBUG			=> 1;

my $lfm_sk;   
my $lfm_user;
my $lfmrc   = "$ENV{'HOME'}/.mpc/last.fm"; # username:sessionkey
my $apikey  = '1dfdc3a278e6bac5c76442532fcd6a05';
my $secret	= 'a70bafc9e39612700a2c1b61b5e0ab61';
my $service = 'http://ws.audioscrobbler.com/2.0/';
my $httpTimeout	= 15;
my $terminal_encoding = $ENV{'LANGUAGE'} || $ENV{'LANG'} || 'en_US.iso8859-1';
   $terminal_encoding =~ s/\w*\.//;
#
# FEEL FREE TO EDIT BELOW THIS LINE
#
binmode STDOUT, ":encoding($terminal_encoding)";
use strict;
use warnings;
use v5.10;

sub call_api20($);
sub printError($$$);

if (-e ! $lfmrc) { 
	printHelp("run get-session_key.sh and set \$lfmrc in lfm.pl"); 
	die "Did you make a session key?"; }

open(CONF, "<$lfmrc") or die "file?";
while (<CONF>) {
	chomp; if (/:/) {
	$lfm_user = $_; $lfm_user = $lfm_user =~ s/:.*//; 
	$lfm_sk = $_; $lfm_sk = $lfm_sk =~ s/.*://;
	}} close(CONF);

if (length($lfm_user)==0 or
	length($lfm_sk)==0) { 
	die "$lfmrc does not contain `user:sessionKey'"; }

my %args_short = (
 '-a'  => {'add'=>'s', 'tag'=>'s' ,              'love'=>'s',                                            }, 
 '-A'  => {            'tag'=>'s'                                                                        },
 '-d'  => {                        'create'=>'s'                                                         }, 
 '-l'  => {'add'=>'i', 'tag'=>'i',               'love'=>'i', 'playlists'=>'i',     'tracks'=>'i'        }, 
 '-n'  => {                        'create'=>'s'                                                         }, 
 '-p'  => {'add'=>'i'                                                                                    }, 
 '-r'  => {            'tag'=>'n',               'love'=>'n', 'playlists'=>'n',     'tracks'=>'n'        }, 
 '-s'  => {                                                   'playlists'=>'{ITt}', 'tracks'=>'{ItA}'    }, 
 '-t'  => {'add'=>'i', 'tag'=>'i',               'love'=>'i'                                             },
 ); my %args_sshort = (
 '-ol' => {            'tag'=>'i'                                                                        },
 '-ta' => {            'tag'=>'s'                                                                        }, 
 '-tA' => {            'tag'=>'s'                                                                        },
 '-tt' => {            'tag'=>'s'                                                                        },
 '-ls' => {            'tag'=>'n'                                                                        },
 ); my %args_long = (
'--t'  => {'add'=>'s',      'tag'=>'s',         'love'=>'s'                                              },
'--p'  => {'add'=>'s'                                                                                    }, 
);
my @all_possible_args = (keys %args_long, keys %args_sshort, keys %args_short);
my @all_singlechar_args = (keys %args_long, keys %args_short);
my %commands = (
	'add'       => { api => 'playlist.addtrack'   , },
	'create'    => { api => 'playlist.create'     , },
	'love'      => { api => 'track.love'          , },
	'playlists' => { api => "user.getplaylists"   , },
	'tracks'    => { api => 'user.getrecenttracks', },
	'tag'       => { mix => 'listtags'            , }
); my %commands_short = (
	a => 'add',
	c => 'create',
	l => 'love',
	p => 'playlists',
	t => 'tracks',
	T => 'tag',
); my %argvalues = ( 
	'n' => 'None',
	's' => 'String',
	'i' => 'Number',
	'I' => 'ID',
	't' => 'Track',
	'T' => 'Title',
	'A' => 'Artist'
);
my %cliargs; #<- sub parse_options
my $command; #<- sub determined_mode
my $invalid='~'; #<- sub option_type_in_mode.
                 #   means illegal option value for mode (ie. add -t zebra, 
				 #   because -t takes an int).

sub determined_mode {
	for (my $i=0; $i<scalar @ARGV; $i++) {
		if (grep { $_ eq $ARGV[$i]} (keys %commands, keys %commands_short)) {
			if  ($i eq 0) { return splice @ARGV, $i, 1; }
			return $ARGV[$i] }}}

sub option_type_in_mode($$){
	my ($opt, $mode) = @_;
	my (%argsa, $type);
	@argsa{keys %args_short} = values %args_short;
	@argsa{keys %args_sshort} = values %args_sshort;
	@argsa{keys %args_long} = values %args_long;
	$mode = $commands_short{$mode} || $mode;
	if (defined($argsa{$opt}{$mode})) { # check if opion is defind in current mode
		return $argsa{$opt}{$mode}; }
	return $invalid; }

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
				$options{$a} = [$optim => 0xc0ffee];

			} elsif (not grep { $_ eq $v} ($invalid, @all_possible_args)) { # "value" == -f ?
				$options{$a} = [$optim => $v];

			} elsif (defined($argvalues{$optim}) and  $argvalues{$optim} eq 'None') {
				$options{$a} = [$optim => 0xc0ffee];

			} else {
				# split {ItA} into "it|track|artist"
				if ($optim =~ /^{(.*)}$/) {
					my %optlist = map { $_ => $argvalues{$_} } split(//, $1);
					$optim = join('|', values %optlist );
				} else {
					$optim = $argvalues{$optim};
				}
				printf "The option %s takes a value of type '%s' in %s mode.\n", $a, $optim, $command;
				exit 1;
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
				$options{$a} = [$optim => 0xc0ffee];
			} else {
				$options{$a} = [$optim => $v];
			}

			#printf "# %3s -> %s: %s\n", $a, option_type_in_mode($a, $command), $v;

		} elsif (grep { $_ eq $a} @all_possible_args) {
			printf "The command '%s' does not take the option -- '%s'\n", $command, $a;
			exit 1;
		} else {
			#printf "'%s' applicable in '%s': >%s<\n", $a, $applicable, $command;
			printf "Illegal option -- '%s'\n", $a;
			exit 1;
		}
		#$argc--;
	}
	return %options;
}


$command = determined_mode(@ARGV);
$command = $commands_short{$command} || $command || '$1';
%cliargs = parse_options();
my $badexit = 1;
my $pebkacExit = 2;
#die "parsed";


#printf "# command: %s; (%s)\n", $command, join(", ", @ARGV);

#
# Check input
#
	#todo push @arr, splice @arr, 0, 1;
	printHelp("Invalid command.",
		"$command should be one of: @{ [sort (keys %commands, keys %commands_short) ] }",
		$badexit)
	unless (grep {/^$command$/} (keys %commands, keys %commands_short));

# assert value type
my %givenArgs;
while ((my $flag, my $value) = each (%cliargs)){
	my $valueType = @$value[0];
	my $parameter = @$value[1];
	printf "got %3s (%s): %-40s \n", $flag, $valueType, $parameter;

	if	($valueType eq 'i') {
	printError('Wrong parameter.', "$command $flag n must be an integer (tID)", $pebkacExit)
	unless ($parameter =~ m/^\d+$/); 

		$givenArgs{$command}{$flag} = int $parameter;

	} else {

		$givenArgs{$command}{$flag} = 1; 
	}
}


my %OPT = ();
$OPT{sk} 			= $lfm_sk;
$OPT{lfm_user}		= $lfm_user;
$OPT{mix_method}	= $commands{$command}{mix}	|| undef;
$OPT{api_method}	= $commands{$command}{api}	|| undef;
$OPT{limit}			= $givenArgs{$command}{'-l'}	|| OUTPUT_LIMIT;
$OPT{reverse} 		= $givenArgs{$command}{'-r'}	|| 0;
$OPT{pid}			= $givenArgs{$command}{'-p'}	|| 0;
$OPT{playlist}		= $givenArgs{$command}{'--p'}	|| "";
$OPT{tid}			= $givenArgs{$command}{'-t'}	|| 0;
$OPT{artist}		= $givenArgs{$command}{'-a'}	|| "";
$OPT{album}			= $givenArgs{$command}{'-A'}	|| "";
$OPT{track}			= $givenArgs{$command}{'--t'}	|| "";
$OPT{name}			= $givenArgs{$command}{'-n'}	|| "";
$OPT{description}	= $givenArgs{$command}{'-d'}	|| "";
$OPT{order_by}		= $givenArgs{$command}{'-s'}	|| "";
$OPT{output_limit}	= $givenArgs{$command}{'-ol'}	|| 20; # max 100 tags
$OPT{tag_artist}	= $givenArgs{$command}{'-ta'}	|| "";
$OPT{tag_album}		= $givenArgs{$command}{'-tA'}	|| "";
$OPT{tag_track}		= $givenArgs{$command}{'-tt'}	|| "";
# --


#
# The rest is magic
#

use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use Encode;
#use English;
use LWP::UserAgent;
use List::Util qw[min max];
#use Switch 'Perl 6';
use Tie::File; 
use URI::QueryParam;
use XML::Simple;



#
# Call the API
#

my	$ua;
	$ua = LWP::UserAgent->new;
	$ua->timeout( $httpTimeout);

call_api20(\%OPT);
exit -1;

sub getXml_api20($){
	#use Switch 'Perl 6';
	
	my %OPT 		= %{ $_[0] };
	my $method 		= $OPT{api_method};
	my %servargs	= ();
	my @xmlargs		= ();

	#print "getxml: $method\n";


	$servargs{api_key}	= $apikey;

	if (requires_authentication($method)){
		$servargs{sk}	= $lfm_sk;
	}


	if ($method eq "user.getrecenttracks") {

		$servargs{method}	= $method;
		$servargs{limit}	= $OPT{'limit'};
		$servargs{page}		= "1";
		$servargs{user}		= $lfm_user;
		#$servargs{from}	= `epoch`;
		#$servargs{to}		= `epoch`;

		@xmlargs = (keyattr => {}, forcearray => 0);
	}

	elsif ($method eq "user.getplaylists") {

		$servargs{method}	= $method;
		$servargs{user}		= $lfm_user;
		$servargs{page}		= "1";
		#$servargs{from}        = `epoch`;
		#$servargs{to}          = `epoch`;

		@xmlargs = (forcearray=>0);
	}
	elsif ($method eq "artist.gettoptags") {
		$servargs{method}	= $method;
		$servargs{artist}	= $OPT{'artist'};
		$servargs{autocorrect} = 1;
		#$mbid				= $OPT{mbid}
	}

	elsif ($method eq "album.gettoptags") {
		$servargs{method}	= $method;
		$servargs{artist}	= $OPT{'artist'};
		$servargs{album}	= $OPT{'album'};
		$servargs{autocorrect} = 1;
		#$mbid				= $OPT{mbid}

	}
	elsif ($method eq "track.gettoptags") {
		$servargs{method}	= $method;
		$servargs{artist}	= $OPT{'artist'};
		$servargs{track}	= $OPT{'track'};
		$servargs{autocorrect} = 1;
		#$mbid				= $OPT{mbid}
	}

	elsif ($method eq "artist.gettags") {
		$servargs{method}	= $method;
		$servargs{artist}	= $OPT{'artist'};
		$servargs{autocorrect} = 1;
		#$mbid				= $OPT{mbid}
	}

	elsif ($method eq "album.gettags") {
		$servargs{method}	= $method;
		$servargs{artist}	= $OPT{'artist'};
		$servargs{album}	= $OPT{'album'};
		$servargs{autocorrect} = 1;
		#$mbid				= $OPT{mbid}

	}
	elsif ($method eq "track.gettags") {
		$servargs{method}	= $method;
		$servargs{artist}	= $OPT{'artist'};
		$servargs{track}	= $OPT{'track'};
		$servargs{autocorrect} = 1;
		#$mbid				= $OPT{mbid}
	} else {
		printError('Missing Arguments', "Routine for fetching xml ($method) is not defined ", $pebkacExit);
	}

	my $response = getResponse(\%servargs, 'utf8');

	#print Dumper($response->decoded_content);

	if ($response->is_success) {
		#print Dumper( XMLin(($response->decoded_content, @xmlargs)) );
		return XMLin(($response->decoded_content, @xmlargs));
	}

	return -1;
}



sub call_api20($){
		#use Switch 'Perl 6';
	my %OPT = %{ $_[0] };
	my %servargs = ();

	my $method 		= $OPT{api_method} || $OPT{mix_method};

	$servargs{method}	= $method;
	$servargs{api_key}	= $apikey;

	if (requires_authentication($method)){
		$servargs{sk}	= $lfm_sk;
	}

	my %opt_recenttracks = (
		api_method	=> $commands{tracks}{api},
		limit		=> $OPT{limit},
		page		=> $OPT{page} || 1,
		user		=> $OPT{user} || $lfm_user,
		#to			=> $OPT{epoch_to} || 0,
		#from		=> $OPT{epoch_frome} || 0,
	);
	my %opt_playlists = (
		api_method	=> $commands{playlists}{api},
		#limit		=> $OPT{limit},
		page		=> $OPT{page} || 1,
		user		=> $OPT{user} || $lfm_user,
	);

	# map -t n to an artist, album and a track
	if ($OPT{tid} != 0){
		my $xml_t 	= getXml_api20(\%opt_recenttracks);
		my $tracks	= $xml_t->{recenttracks}{track} ;
		my $idlist_t= mapTrackIds($tracks);
		my $idx		= 0;
		while ( ((my $aidx, my $lsid) = each %$idlist_t) && ! $idx){
			if ($OPT{tid} == $lsid) {
				$idx = $aidx;
			}
		}
		$servargs{artist}	= $tracks->[$idx]->{artist}{content};
		$servargs{album}	= $tracks->[$idx]->{album}{content} || "";
		$servargs{track}	= $tracks->[$idx]->{name};
		$OPT{artist}		= $servargs{artist};
		$OPT{album}			= $servargs{album};
		$OPT{track}			= $servargs{track};
	} else {
		$servargs{artist}	= $OPT{artist};
		$servargs{album}	= $OPT{album};
		$servargs{track}	= $OPT{track};
	}

	my %opt_toptags = (
		artist		=> $OPT{artist},
		album		=> $OPT{album},
		track		=> $OPT{track},
	);

	# api {artist,album,track}.removetag takes only one tag at a time
	if ($method =~ m/.*removetag/){

		print "$method\n";

		foreach my $aat (('tag_artist','tag_album','tag_track')) {
			print "aat: $aat>\n";
			my @tags = split /,/,$OPT{$aat};
			my %OPT_TEMP = %OPT;
			my $tag;

			if (scalar (@tags) >1 ){

				print "Many tags: @tags\n";


				foreach $tag (@tags){
					$OPT_TEMP{$aat} = $tag;
					call_api20(\%OPT_TEMP);
					print "\n";
				}
			} else {
				print "Single tag <$OPT{$aat}> ($aat)\n";
				#call_api20(\%OPT);
				#return 0;
				#$OPT{$aat} 
			}
		}
	}


	my $call = $servargs{method};

	if ($call eq "track.love") {

		if ($OPT{reverse} == 1){
			$servargs{method} = 'track.unlove';
		}

	} elsif ($call eq "playlist.create") {

		$servargs{title}		= $OPT{name};
		$servargs{description}	= $OPT{description};

	} elsif ($call eq "playlist.addtrack") {
		# map --p or -p to a playlist id
		my $xml_p	= getXml_api20(\%opt_playlists);
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

		printWarning("No such playlist") if (! $lfm_plid );
		printWarning("Bad artist name") if ($servargs{artist} =~ m/^$/ );
		printWarning("Bad track name") if ($servargs{track} =~ m/^$/ );

		$servargs{playlistID}	= $lfm_plid;

	} elsif ($call eq "user.getplaylists") {

		#my $xml 	= getXml_api20("user.getplaylists");
		my $xml 	= getXml_api20(\%OPT);
		my $pls_ref	= $xml->{playlists}->{playlist};
		my %pls		= %{ $pls_ref };
		my $idlist  = mapPlaylistIds($pls_ref);
		my $format	= "% 6s % 3s  %s \n";
		my $sort_sub= \&sortPlaylistByTitle;
		if ($OPT{order_by} eq "id" ){
			$sort_sub = \&sortPlaylistById
		} 
		elsif ($OPT{order_by} eq "track" ) {
			$sort_sub = \&sortPlaylistByTrack
		}

			printf {*STDOUT}  $format, "len", "pID", "Playlist" ; 
		foreach my $id ( $sort_sub->( $pls_ref, $OPT{reverse})) { 
			printf {*STDOUT}  $format, 
			$pls{$id}{size},
			$idlist->{$id}, 
			$pls{$id}{title} ; 
		}
		return 0;

	} elsif ($call eq "user.getrecenttracks") {
		my $maxa = 0;
		my $maxt = 0;
		my $maxid = 2 +(length $OPT{'limit'});
	
		#my $xmlresponse = getXmlRecentTracks();
		my $xml		= getXml_api20({
				api_method	=> $commands{tracks}{api},
				limit		=> $OPT{limit},
				page		=> $OPT{page} || 1,
				user		=> $OPT{user} || $lfm_user,
				#to			=> $OPT{epoch_to} || 0,
				#from		=> $OPT{epoch_frome} || 0,
			});
		my $tracks	= $xml->{recenttracks}{track} ;
		my @tracks	= @{ $tracks };
		my $sort_sub= \&sortTracksByDate;
		my $idlist	= mapTrackIds($tracks);
		my $format	= 
			"% ".$maxid."s %02s:%02s % ".$maxa."s - %- ".$maxt."s\n";

		if (		$OPT{order_by} eq 'title' ) {
			$sort_sub = \&sortTracksByTitle 
		} elsif (	$OPT{order_by} eq 'artist' ) {
			$sort_sub = \&sortTracksByArtist 
		}

		my @sorted	= $sort_sub->($tracks, $OPT{reverse});
	
		#find longest name or title
		foreach (@tracks){
			my $name 	= $_->{name};
			my $artist	= $_->{artist}->{content};
			$maxa = max(length($artist), $maxa);
			$maxt = max(length($name), $maxt); }
			$maxa = min(WIDTH_ARTIST, $maxa);
			$maxt = min(WIDTH_SONG, $maxt);
			$maxt += 4-($maxid);
	
	
			printf {*STDERR}  $format, 
				"tID", "hh", "mm", 
				"Artist", "Track";
	
		foreach (@sorted){
	
			my $trk		= $tracks[$_];
			my $epoch	= $trk->{date}->{uts} || time;
			my $name 	= $trk->{name};
			my $artist	= $trk->{artist}->{content};
	
			#my ($sec, $min, $hour, $day,$month,$year) = 
			#	(localtime($epoch))[0,1,2,3,4,5,6]; 
			my ($min,$hour) = (localtime($epoch))[1,2] ;
	
			printf {*STDOUT} $format, 
				$idlist->{$_}, $hour, $min, 
				$artist, $name;
		}
		return 0;
	} elsif ($call eq "listtags") {
		sub printTags($$$$){
			my $prefix		= 	$_[0];
			my $command		= 	$_[1];
			my %opt_toptags = %{$_[2]};
			my %OPT			= %{$_[3]};
			my $tagsfor		= $OPT{$prefix};

			my @ordered = ();
			my %tags	= ();
			my $xml		= ();
			my $max		= 0;
			my $line	= 0;
			my $onetoptag =	0;
			my $appliedtags = 0;

			$opt_toptags{api_method} = "$prefix.$command";
			$xml		= getXml_api20(\%opt_toptags);

			if ($command eq 'gettoptags'){
				print "$prefix: $tagsfor\n    ";
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
					print "    Saved:\n    ";
					@ordered 	= sort keys %tags;
				} else {
					@ordered	= sort { 
						$tags{$b}{count}
						<=>
						$tags{$a}{count}
					} keys %tags;
				}
				$max = min($OPT{output_limit}, scalar (@ordered) );
				$line = length("$tagsfor: ");
				for (my $i=0; $i< $max; $i++){
					$line += length("$ordered[$i], ");
					if ( $line <= 80) {
						print $ordered[$i];
						print ", " unless ($i+1 == $max);
					} else {
						print "\n";
						#for (my $c=0; $c< length($tagsfor); $c++){
						#	print " ";
						#}
						#print "  ";
						print "    ";
						print $ordered[$i];
						print ", " unless ($i+1 == $max);
						$line =4;
						$line += length($ordered[$i]) + 2;
						
					}
				}
			} else {
				print "No tags";
			}
			print "\n";
			if ($command eq 'gettags' && scalar @ordered >= 1){
			print "\n";
			}
		}

		if ($OPT{tag_artist} ne "") { 
			if ($OPT{reverse}){
				$OPT{api_method} = "artist.removetag";
			} else {
				$OPT{api_method} = "artist.addtags";
			}
			call_api20(\%OPT); 
		}
		if ($OPT{tag_album} ne "") { 

			if ($OPT{reverse}){
				$OPT{api_method} = "album.removetag";
			} else {
				$OPT{api_method} = "album.addtags";
			}

			call_api20(\%OPT); 
		}
		if ($OPT{tag_track} ne "") { 
			if ($OPT{reverse}){
				$OPT{api_method} = "track.removetag";
			} else {
				$OPT{api_method} = "track.addtags";
			}
			call_api20(\%OPT); 
		}



		if ( $OPT{artist} ne "" ){	printTags("artist","gettoptags",\%opt_toptags,\%OPT); }
		if ( $OPT{artist} ne "" ){	printTags("artist","gettags",\%opt_toptags,\%OPT); }

		if ( $OPT{album} ne "" ){ 	printTags("album", "gettoptags",\%opt_toptags,\%OPT); }
		if ( $OPT{album} ne "" ){ 	printTags("album", "gettags",\%opt_toptags,\%OPT); }

		if ( $OPT{track} ne "" ){ 	printTags("track", "gettoptags",\%opt_toptags,\%OPT); }
		if ( $OPT{track} ne "" ){ 	printTags("track", "gettags",\%opt_toptags,\%OPT); }

		if ($OPT{artist} eq "" && $OPT{album} eq "" && $OPT{track} eq ""){
			printHelp();
		}

		return 0;

	} elsif ($call eq "artist.addtags") { $servargs{tags}	= $OPT{tag_artist};
	} elsif ($call eq  "album.addtags") { $servargs{tags}	= $OPT{tag_album};
	} elsif ($call eq  "track.addtags") { $servargs{tags}	= $OPT{tag_track};
	} elsif ($call eq "artist.removetag") { $servargs{tag}	= $OPT{tag_artist};
	} elsif ($call eq  "album.removetag") { $servargs{tag}	= $OPT{tag_album};
	} elsif ($call eq  "track.removetag") { $servargs{tag}	= $OPT{tag_track}; 
	} else {
		printError('Not Implemented', (caller(0))[3].": Routine not defined for $OPT{api_method}", $badexit); 
		exit 1;
	}
 
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
	}	
	print "$confirmation\n";
	return 0;
}

##
## HELPERS 
##

sub getResponse($$){

	my %servargs;
	my $response;
	my $incoding;
	my $audioscrobbler	= URI->new($service);

	if (ref $_[0] ne 'HASH') {
		printError('No parameters', (caller(0))[3].": please pass a hash reference", $badexit)
	}

	%servargs = %{ $_[0] };
	$incoding = $_[1];
	my %unicode_param = ();


	while ((my $k,my $v)=each %servargs){ 
		if (lc $incoding eq 'utf8'){
			#skip
		} else {
			$k = encode_utf8($k);
			$v = encode_utf8($v);
		}
		$unicode_param{$k} = $v;
		$audioscrobbler->query_param($k, $v );
	} 

	#if (DEBUG){ 
	#	print "\n getResp: $servargs{method}\n"; 
	#	while ((my $k,my$v)=each %servargs){
	#		printf " !sk  % 10s: %s u: %s\n", $k,$v, $unicode_param{$k};
	#	}
	#}


	my	$ms	 = "";
	if ($servargs{'sk'}){ 
		foreach my $key (sort keys %unicode_param) {
			my $val = $unicode_param{$key};
			$ms .= $key.$val;
		}
			$ms .= $secret; 
			$ms	 = md5_hex($ms);
		$audioscrobbler->query_param('api_sig', $ms);
		$servargs{api_sig} = $ms;

		$response = $ua->post($audioscrobbler);
		$audioscrobbler->query_param('sk', '');
	} else {
		$response = $ua->get($audioscrobbler);
	}



	unless ($response->is_success) {
		printWarning((caller(0))[3]."($servargs{method}): ".$response->status_line );

		if ($response->decoded_content){
			my $error = XMLin($response->decoded_content);
			printWarning($error->{error}{content});
		}
	} 
	return $response
}


sub requires_authentication($){
	my $method = $_[0];
	my $need_auth = grep {/^$method$/} (
		'track.love', 
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
	);
	return $need_auth;
}

sub mapTrackIds($$) {

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
sub mapPlaylistIds($$){
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

sub printError($$$) {
	(my $context, my $error, my $code) = @_;
	$code = $code || 1;
	printf STDERR "%s\n  %s\n", $context, $error ;
	exit $code;
}

sub printWarning($) { printError('warning', $_[0], 0); }

sub printHelp {
	(my $context, my $error, my $code) = @_;

	# todo: allow songs be named [0-9]*
	my $help =<< 'EOH'
	.usage: $0: <command> [options]
	. where command is one of 
	.   add        (a)      append song to playlist
	.   create     (c)      new playlist
	.   love       (l)      <3 a track
	.   playlists  (p)      show playlists
	.   tracks     (t)      show recent scrobbles
	.   tag        (T)      add or list tags
	.
	. applicability of options:
	.   add        -p pID | --p.NAME { -t tID | --t t.TITLE -a NAME}
	.   create     -d DESCRIPTION -n NAME
	.   love       [ -r (unlove)   ]    { -t tID | --t t.TITLE -a NAME}
	.   playlists  [ -l n ][ -s id | title | Tracks]
	.   tracks     [ -l n ][ -s id | title | artist]
	.   tag        -a artist -A album -t tID --t track -ls
	.
	. general options
	.   -r                  reverse sort order (or unlove)
	.   -l <N>              limit output to N lines
	.   -s                  sort output by a given column
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
	$help =~ s/\$0/$0/;
	print STDERR "$help\n";
	printError($context, $error, $code)
}
