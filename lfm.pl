#!/usr/bin/perl -w
use strict;
use warnings;

use Data::Dumper;
use Digest::MD5 qw(md5_hex);
use Encode;
use English;
#use File::Basename;
use LWP::UserAgent;
use List::Util qw[min max];
use Switch 'Perl 6';
use Tie::File; 
use URI::QueryParam;
use XML::Simple;

#$Data::Dumper::Indent = 1;
#$Data::Dumper::Pair = " => ";
#use Term::ANSIColor qw(:constants);
#$Term::ANSIColor::AUTORESET = 1;



use constant OUTPUT_LIMIT	=> 14; # lines
use constant WIDTH_ARTIST	=> 43;
use constant WIDTH_SONG		=> 23;

open(CONF, "<$ENV{'HOME'}/.mpc/last.fm") or die "Did you make a session key?: cant read: $!";
		my @conflines = <CONF>;
chomp( 	my $lfm_user = (split /:/, $conflines[0])[0]); 
chomp( 	my $lfm_sk 	= (split /:/, $conflines[0])[1]); 
close(CONF);

my $service				= 'http://ws.audioscrobbler.com/2.0/';
my $apikey 				= '1dfdc3a278e6bac5c76442532fcd6a05';
my $secret				= 'a70bafc9e39612700a2c1b61b5e0ab61';


my $httpTimeout			= 15;
my $terminal_encoding	= 'utf8';
my %servargs			= ();
   $servargs{api_key} 	= $apikey;
my	$ua 				= LWP::UserAgent->new;
	$ua->timeout(
		$httpTimeout);
my $audioscrobbler		= URI->new($service);

#my $xs					= new XML::Simple( KeyAttr => [ ],);

my %OPT = ();
#my $OPT_limit;
#my $OPT_reverse;
#my $OPT_pid;
#my $OPT_tid;
#my $OPT_artist;
#my $OPT_track;
#my $OPT_name;
#my $OPT_description;
#my $OPT_order_playlist;
#my $OPT_order_tracks;


parseArguments();
binmode STDOUT, ":encoding($terminal_encoding)";

## 
## FEEL FREE TO EDIT BELOW THIS LINE
##


sub parseArguments {

	my %cmds = (
		add 		=> { long 	=> \&playlist_addTrack, 
						 short 	=> \&addTrackToPlaylistById,
				 	},
		create 					=> \&createPlaylist, 
		love		=> { long	=> \&trackLove,
						 short	=> \&trackLoveById,
						 long_r => \&trackUnLove,
						 short_r=> \&trackUnLoveById, 
				 	},
		playlists				=> \&listPlaylists, 
		tracks					=> \&listRecentScrobbles,
	);
	my %cmd_s2l = (
		a => 'add',
		c => 'create',
		l => 'love',
		p => 'playlists',
		t => 'tracks',
	);

	##$cmds{a} = \$cmds{$cmd_s2l{a}};
	##$cmds{c} = \$cmds{$cmd_s2l{c}};
	##$cmds{l} = \$cmds{$cmd_s2l{l}};
	##$cmds{p} = \$cmds{$cmd_s2l{p}};
	##$cmds{t} = \$cmds{$cmd_s2l{t}};
	#foreach (keys %cmd_s2l){
	#	$cmds{$_} = \$cmds{$cmd_s2l{$_}};
	#}

	# any - anything goes
	# int - integers
	# []  - list of possible values
	my %args = (
	 '-a' => {	add=>	'any', 
				love=>	'any' 				}, 
	 '-d' => {	create=>'any' 				}, 
	 '-l' => {	add =>		'int', 
		 		love=>		'int', 
				playlists=>	'int',
				tracks=>	'int'			}, 
	 '-n' => {	create=>'any' 				}, 
	 '-p' => {	add=>		'int'			}, 
	'--p' => {	add=>	'any'				}, 
	 '-r' => {	love=>				'na',
		 		playlists=>			'na', 
				tracks=>			'na'	}, 
	 '-s' => {	playlists=>	['id','title','track'], 
		 		track=>		['id','track','artist'] }, 
	 '-t' => {	add=>		'int',
		 		love=>		'int'			},
	'--t' => { 	add=>	'any',
				love=>	'any' 				},

	 #'--' => { playlists=>'filter' }, 
	 #'-x' => { add=>'any'}, 
	 #'-y' => { add=>'any'}, 
	 #'-f' => { add=>'any'}, 
	 #'-g' => { add=>'any'}, 
	 #'-c' => { add=>'any'}, 
	);


	my %xargs = (
		add	=>	{
					'-p' => [[ '--p' ]],
					'-t' => [[ '--t' ]],
					'-a' => [['-t']],
				},
		love => {
					'-t' => [[ '--t' ]],
					'-a' => [['-t']],
				}
		#tracks => 
	);
	my $argc = @ARGV;
	my %givenArgs = ();
	my $argval_consumed = 0;
	my $cmd = $ARGV[0] || '<none>'; 
	   $cmd = $cmd_s2l{$cmd} || $cmd;

	
	printHelp("Invalid command: $cmd should be one of: @{[sort keys %cmds]}")
		unless (grep {/^$cmd$/} (keys %cmds));


	# general strategy: 
	#  check that -arg is in %args
	#  check that command is a key in the '-a' hash or %args
	#    find out what kind of value -arg takes (int/any/list)
	#      print help or assign value 

	while ($argc > 1) {

		$a = splice @ARGV, 1, 1;
		$argc--;

		my $arg_ref		= $args{$a};
		my @modes4arg	= keys %$arg_ref;
		my $a_ref		= \$args{$a}{$cmd}; 		# -r -> add -> any
		#my $ga_ref		= \$givenArgs{$a}{$cmd};	# checked arguments
		my $argval		= $ARGV[1] || \\0;
		my $mode_arg	= grep {/$cmd/} @modes4arg;



		printHelp("Invalid argument: $a") unless grep /$a/, %args;
		printError("Invalid argument: command $cmd does not take argument $a") 
			unless $mode_arg;

		$argval_consumed = 1;

		if	($$a_ref eq 'any') {
			printHelp("argument $_[0] needs a value") 
				unless ref $argval ne 'REF';

			$givenArgs{$cmd}{$a} = $argval;

		} elsif	($$a_ref eq 'int') {
			printError( "$cmd $a n must be an integer (tID)") 
				unless ( ref $argval ne 'REF' && 
					$argval =~ m/^\d+$/ );

			$givenArgs{$cmd}{$a} = int $argval;

		} elsif	(ref $$a_ref eq 'ARRAY' ) {
			printHelp("$cmd $a must be one of: @{$$a_ref}") 
				unless (grep {/$argval/} @{$$a_ref} );

			$givenArgs{$cmd}{$a} = $argval; 

		} elsif	($$a_ref eq 'filter') {

			# TODO make filters work
			$givenArgs{$cmd}{$a} .= $argval; 

		} else {

			$givenArgs{$cmd}{$a} = 1; 
			$argval_consumed = 0;
		}

		if ($argval_consumed) { 
			my $cut = splice(@ARGV, 1, 1);
			$argc--;
			$argval_consumed = 0;
		}
	}


#	#print Dumper( %givenArgs);
#	foreach my $key (keys %givenArgs) {
#		foreach my $mode (keys %{$givenArgs{$key}}){
#			my $val = $givenArgs{$key}{$mode} || 1;
#			print "$key\t- $mode\t- $val \n";
#		}
#	}

	# verify that no conflicting arguments are given
	foreach my $a (keys %{$givenArgs{$cmd}}){
		my $nocrash = 1; # todo - maybe cycle through everything and collect all
						 # errors instead of exiting on 1st found
		my $cxalr 		= $xargs{$cmd} || {};
		my %cmd_xargs	= %$cxalr;
		my @cakeys		= keys %cmd_xargs;
		my $cakidx		= 0;
			my $lists;
			my $lidx;
				my @list;
				my $single;
				my $combined;
					my $alltrue;
					my $comidx;
		if ($xargs{$cmd}{$a}) {
			while ($nocrash && $cakidx < scalar @cakeys ){
				if ( $a ne $cakeys[$cakidx]) { $cakidx++; next; }
				$lists 		= $cmd_xargs{$cakeys[$cakidx++]};
				$lidx 		= 0;
				while ($nocrash && $lidx < scalar @$lists) { 
					@list 		= @{ $lists->[$lidx++] };
					$single		= scalar (@list) == 1;
					$combined	= scalar (@list) >  1;
					if (grep {/^$a$/} @list) { 
						next; 
					} else {
						if ($combined) {
							$alltrue	= 1;
							$comidx 	= 0;
							while ($alltrue && $comidx < scalar @list){
								$alltrue = 
								$alltrue && $givenArgs{$cmd}{$list[$comidx]};
								$comidx++; }
							printError("$cmd $a: invalid argument combination @list")
							if ($alltrue) 

						} elsif ($single) {
							printError("$cmd $a: invalid argument combination $list[0]")
							if ($givenArgs{$cmd}{$list[0]});
						}
					}
				}
			}
		} 
	}



	$OPT{'limit'}		= $givenArgs{$cmd}{'-l'}	|| OUTPUT_LIMIT;
	$OPT{'reverse'} 	= $givenArgs{$cmd}{'-r'}	|| 0;
	$OPT{'pid'}			= $givenArgs{$cmd}{'-p'}	|| 0;
	$OPT{'tid'}			= $givenArgs{$cmd}{'-t'}	|| 0;
	$OPT{'artist'}		= $givenArgs{$cmd}{'-a'}	|| "";
	$OPT{'track'}		= $givenArgs{$cmd}{'--t'}	|| "";
	$OPT{'name'}		= $givenArgs{$cmd}{'-n'}	|| "";
	$OPT{'description'}	= $givenArgs{$cmd}{'-d'}	|| "";
	$OPT{'order_playlist'}	= \&sortPlaylistByTitle;
	$OPT{'order_tracks'}	= \&sortTracksByDate;



	if ($cmd eq "playlists") {
		$givenArgs{$cmd}{'-s'} = $givenArgs{$cmd}{'-s'} || 'title';
	}
	if ($cmd eq "tracks") {
		$givenArgs{$cmd}{'-s'} = $givenArgs{$cmd}{'-s'} || 'id';
	}

	if ( $cmd eq "tracks" && $givenArgs{$cmd}{'-s'} eq 'id' ){
		$OPT{'order_tracks'} = \&sortTracksByDate; }
	if ( $cmd eq "tracks" && $givenArgs{$cmd}{'-s'} eq 'track' ){
		$OPT{'order_tracks'} = \&sortTracksByTitle;}
	if ( $cmd eq "tracks" && $givenArgs{$cmd}{'-s'} eq 'artist' ){
		$OPT{'order_tracks'} = \&sortTracksByArtist; }

	if ( $cmd eq "playlists" && $givenArgs{$cmd}{'-s'} eq 'track' ){
		$OPT{'order_playlist'} = \&sortPlaylistByTrack; }
	if ( $cmd eq "playlists" && $givenArgs{$cmd}{'-s'} eq 'id' ){
		$OPT{'order_playlist'} = \&sortPlaylistById; }
	if ( $cmd eq "playlists" && $givenArgs{$cmd}{'-s'} eq 'title' ){
		$OPT{'order_playlist'} = \&sortPlaylistByTitle; }
	
	given ($cmd) {
	when "add"		{ 	$cmds{$cmd}{short}->(
							$givenArgs{$cmd}{'-t'},
							$givenArgs{$cmd}{'-p'}||
							$givenArgs{$cmd}{'--p'}
							) unless (	$givenArgs{$cmd}{'-a'} );

						if ($givenArgs{$cmd}{'-a'}) {

						$cmds{$cmd}{long}->(
							$givenArgs{$cmd}{'-t'}||
							$givenArgs{$cmd}{'-t'},
							$givenArgs{$cmd}{'-a'},
							$givenArgs{$cmd}{'-p'}||
							$givenArgs{$cmd}{'--p'});
						}
					}
	when "create"	{	$cmds{$cmd}->(
							$givenArgs{$cmd}{'-n'},
							$givenArgs{$cmd}{'-d'}
							) if ($givenArgs{$cmd}{'-n'} );
							unless ($givenArgs{$cmd}{'-n'} ){
								print "need -n [and -d]\n";
							}
					}
	when "love"		{	$cmds{$cmd}{long}->(
							$givenArgs{$cmd}{'--t'},
							$givenArgs{$cmd}{'-a'}
							) unless ( 	$givenArgs{$cmd}{'-r'} || 
										$givenArgs{$cmd}{'-t'} );
						$cmds{$cmd}{long_r}->(
							$givenArgs{$cmd}{'--t'},
							$givenArgs{$cmd}{'-a'}
							) unless ( 	$givenArgs{$cmd}{'-t'} );
						$cmds{$cmd}{short}->(
							$givenArgs{$cmd}{'-t'}
							) unless (	$givenArgs{$cmd}{'-r'});
						$cmds{$cmd}{short_r}->(
							$givenArgs{$cmd}{'-t'});
					}
	when "playlists"{	$cmds{$cmd}->(
							$givenArgs{$cmd}{'-n'},
							$givenArgs{$cmd}{'-d'});
					}
	when "tracks"	{	$cmds{$cmd}->();
					}
	}

	exit -1;
}


sub printError {
	my $error =  $_[0] || "";
	my $help = "\nERROR:\n$error \n" unless (length $error <= 0);
	print STDERR $help;
	exit -1;
}

sub printWarning {
	my $error =  $_[0] || "";
	my $help = "\nWARNING:\n$error \n" unless (length $error <= 0);
	print STDERR $help;
}

sub printHelp {
	my $error =  $_[0] || "";

	# TODO allow songs be named [0-9]*
	(my $help =<< 'EOH');
	.usage: $0: <command> [options]
	. where command is one of 
	.   add        (a)      append song to playlist
	.   create     (c)      new playlist
	.   love       (l)      <3 a track
	.   playlists  (p)      show playlists
	.   tracks     (t)      show recent scrobbles
	.
	. applicability of options:
	.   add        -p { pID | name } -t { tID | TITLE } -a NAME
	.   create     -d DESCRIPTION -n NAME
	.   love       [ -r (unlove)   ] -t { tID | TITLE } -a NAME
	.   playlists  [ -l n] [ -s { id | title | track  }]
	.   tracks     [ -l n] [ -s { id | title | artist }]
	.
	. general options
	.   -r                  reverse sort order (or unlove)
	.   -l <N>              limit output to N lines
	.   -s                  sort output by id, title or artist
EOH
	$help =~ s/^\t+\.//gm;
	$help =~ s/\$0/$0/;
	$help .= "\nERROR:\n$error \n" unless (length $error <= 0);
	print STDERR $help;
	exit;
}


sub getXmlRecentTracks {

	$servargs{method}	= "user.getrecenttracks";
	$servargs{limit}	= $OPT{'limit'};
	$servargs{page}		= "1";
	$servargs{user}		= $lfm_user;
	#$servargs{from}	= `epoch`;
	#$servargs{to}		= `epoch`;

	my $MAX_TRACKS = 200; # Defaults to 50. Maximum is 200. (API 2.0)


	if ($servargs{limit} > $MAX_TRACKS ) {
		printWarning((caller(0))[3].": limit of $MAX_TRACKS tracks exceeded ");

	}


	my $response = getResponse(\%servargs);
	
	if ($response->is_success) {
		return XMLin(
			$response->decoded_content, 
			keyattr => {  },
			#keyattr => { track=>'date' },
			forcearray => 0,
		);
	}

	printError((caller(0))[3].": Failed to fetch data");
	return -1;
}

sub getResponse($){
	my %servargs;
	my $response;

	printError("getResponse(): please pass a hash reference")
	if (ref $_[0] ne 'HASH');

	%servargs = %{$_[0]};

	while ( (my $k,my $v)=each %servargs){ 
		$audioscrobbler->query_param($k, $v);
	} 

	$response = $ua->get($audioscrobbler);

	if (! $response->is_success) {
		printWarning((caller(0))[3].": ".$response->status_line );
	}

	return $response
}

sub getXmlRecentTracksAlt {

	$servargs{method}	= "user.getrecenttracks";
	$servargs{limit}	= $OPT{'limit'};
	$servargs{page}		= "1";
	$servargs{user}		= $lfm_user;
	#$servargs{from}	= `epoch`;
	#$servargs{to}		= `epoch`;

	foreach my $param (sort keys %servargs){
		$audioscrobbler->query_param($param, $servargs{$param}); }

	my $response = $ua->get($audioscrobbler);

	if ($response->is_success) {

			#print Dumper($response->decoded_content);

		my $xs 	= new XML::Simple(
				);
		print Dumper( 
			XMLin( 
					$response->decoded_content, 
					keyattr => { track => 'date'},
					forcearray => 0,
		));
		#print Dumper(  $response->decoded_content);


	} else {
		print STDERR $response->status_line, "\n";
	}
}

sub getXmlPlaylists {

	$servargs{method}	= "user.getplaylists";
	$servargs{user}		= $lfm_user;

	foreach my $param (sort keys %servargs){ 
		$audioscrobbler->query_param($param, $servargs{$param}); 
	}

	my $response 		= $ua->get($audioscrobbler);

	if ($response->is_success){
		return XMLin( $response->decoded_content, forcearray => 0);
	} else {
		print STDERR $response->status_line, "\n";
	}
}

sub mapTrackIds($){

	my $tracks = $_[0];

	my @sorted = sortTracksByDate($tracks);
	my %idlist = ();
	my $len = @sorted;
	my $backwards = 0;

	# make shortcuts
	foreach (@sorted){
		if ($OPT{'reverse'}){
			$idlist{$_} = ++$backwards;
		} else {
			$idlist{$_} = $len--;
		}
	}
	return \%idlist;

}

sub listRecentScrobbles {

	my $maxa = 0;
	my $maxt = 0;
	my $maxid = 2 +(length $OPT{'limit'});

	my $xmlresponse = getXmlRecentTracks();
	my $tracks = $xmlresponse->{recenttracks}{track} ;
	my @tracks = @{ $tracks };
	my @sorted = $OPT{'order_tracks'}->($tracks);

	my $idlist = mapTrackIds($tracks);

	#find longest name or title
	foreach (@tracks){
		my $name 	= $_->{name};
		my $artist	= $_->{artist}->{content};
		$maxa = max(length($artist), $maxa);
		$maxt = max(length($name), $maxt); }
		$maxa = min(WIDTH_ARTIST, $maxa);
		$maxt = min(WIDTH_SONG, $maxt);
		$maxt += 4-($maxid);

	my $format = "% ".$maxid."s %02s:%02s % ".$maxa."s - %- ".$maxt."s\n";

	printf {*STDERR}  $format, "tID", "hh", "mm", "Artist", "Track";

	foreach (@sorted){

		my $trk		= $tracks[$_];
		my $epoch	= $trk->{date}->{uts} || time;
		my $name 	= $trk->{name};
		my $artist	= $trk->{artist}->{content};

		#my ($sec, $min, $hour, $day,$month,$year) = 
		#	(localtime($epoch))[0,1,2,3,4,5,6]; 
		my ($min,$hour) = (localtime($epoch))[1,2] ;

		printf {*STDOUT} $format, 
		#$idlist->{$_}, $hour, $min, $artist, $name;
			$_ + 1, $hour, $min, $artist, $name;
	}
}


sub mapPlaylistIds($){
	my $xmlref	= $_[0];
	my $len		= keys %{ $xmlref };
	my %idlist	= ();

	my $global_so = $OPT{'reverse'};
	$OPT{'reverse'} = 1;
	foreach my $id ( sortPlaylistById( $xmlref )) { 
		$idlist{$id} = $len--;
	}
	$OPT{'reverse'} = $global_so;
	return \%idlist
}

sub listPlaylists {

	my $xml 	= getXmlPlaylists();
	my $pls_ref	= $xml->{playlists}->{playlist};
	my %pls		= %{ $pls_ref };
	my $idlist  = mapPlaylistIds($pls_ref);

	my $format	= "% 6s % 3s  %s \n";

		printf {*STDOUT}  $format, "len", "pID", "Playlist" ; 

	foreach my $id ( $OPT{'order_playlist'}->( $pls_ref )) { 
		printf {*STDOUT}  $format, 
		$pls{$id}{size},
		$idlist->{$id}, 
		$pls{$id}{title} ; 
	}
}

sub addTrackToPlaylistById($$) {

	(my $tid, my $plid) = @_;


	my $xml = getXmlRecentTracks();
	my $tracks = $xml->{recenttracks}{track} ;
	my $idlist = mapTrackIds($tracks);

	my $idx = 0;

	while ( ((my $aidx, my $lsid) = each %$idlist) && ! $idx){
		if ($tid == $lsid) {
			$idx = $aidx;
		}
	}


	my $ok = playlist_addTrack( 
		$tracks->[$idx]->{name},
		$tracks->[$idx]->{artist}{content},
		$plid
	); 

	if ($ok != 0 ){
		print "$tracks->[$idx]->{name}\n";
		print "$tracks->[$idx]->{artist}{content}\n";
		print "$plid\n";
	}
}

sub playlist_addTrack($$$) {

	printWarning("playlist_addTrack(): missing parameters") if grep( /^$|0/, @_);

	(my $track, my $artist, my $plid) = @_;


	my $xml		= getXmlPlaylists();
	my $pls_ref	= $xml->{playlists}->{playlist};
	my $idlist	= mapPlaylistIds($pls_ref);

	my $lfm_plid= 0;


	if ($plid !~ /^\d+$/ ) {

		my	$andexpr = "";
		foreach (split /\s+/, $plid ){
			$andexpr = $andexpr . "/$_/ && "; }
			$andexpr =~ s/&&\s?\z//;
			$andexpr =~ s,^$,/.*/,;

		# TODO rewrite without using 3 extra lists
		my @plids =();
		my @plnms =();
		my @found =();
		
		foreach (keys %$pls_ref){
			push @plids, $_;
			push @plnms, $pls_ref->{$_}->{title};
		}

		my $m = 0;
		for (my $i=0; $i<$#plids; $i++){
			if (grep {eval $andexpr} $plnms[$i] ){
				push @found, $plnms[$i];
				$m++;
				if ($m>=2){
					$i = $#plids;
					print "add $artist - $track to which playlist?\n";
					foreach (@found){ print "$_\n"; }
					exit 1;
				} else {
					$lfm_plid = $plids[$i];
				}
			}
		}
	} else {
		while ( ((my $lfmid, my $lsid) = each %$idlist) && ! $lfm_plid){
			if ($plid == $lsid) {
				$lfm_plid = $lfmid;
			}
		}
	}

	printWarning("No such playlist") if (! $lfm_plid );
	printWarning("Bad artist name") if ($artist =~ m/^$/ );
	printWarning("Bad track name") if ($track =~ m/^$/ );


	# fill in parameters

	$servargs{method}		= "playlist.addtrack";
	$servargs{sk}			= $lfm_sk;
	$servargs{artist}		= $artist;
	$servargs{track}		= $track;
	$servargs{playlistID}	= $lfm_plid;

	getSignedMethod(\%servargs);

#	# sign the method
#
#	my $ms = "";
#	foreach my $key (sort keys %servargs){
#		$ms .= encode_utf8($key) . encode_utf8($servargs{$key});
#		$audioscrobbler->query_param($key, encode_utf8($servargs{$key}));
#	}
#		$ms .= encode_utf8($secret); 
#		$ms = md5_hex($ms);
#		$audioscrobbler->query_param('api_sig', encode_utf8($ms));

	# post the request

	my $response = $ua->post($audioscrobbler);
	$audioscrobbler->query_param('sk', "");
	

	if ($response->is_success) {

		printf {*STDOUT} "added %s - %s to %s\n", $artist, $track,
				$pls_ref->{$lfm_plid}{title};
		return 0;


	} else {
		print STDERR $response->status_line, "\n";
		my $error = XMLin($response->decoded_content);
		print $error->{error}{content} . "\n";
		return 1;
	}
}

sub createPlaylist($$){

	(my $playlist_title, my $playlist_description) = @_;

	$servargs{method}		= "playlist.create";
	$servargs{title}		= $playlist_title;
	$servargs{description}	= $playlist_description;
	$servargs{sk}			= $lfm_sk;

	getSignedMethod(\%servargs);

#	my $ms = "";
#	foreach my $key (sort keys %servargs){
#		$ms .= encode_utf8($key) . encode_utf8($servargs{$key});
#		$audioscrobbler->query_param($key, encode_utf8($servargs{$key}));
#	}
#		$ms .= encode_utf8($secret); 
#		$ms = md5_hex($ms);
#		$audioscrobbler->query_param('api_sig', encode_utf8($ms));


	my $response = $ua->post($audioscrobbler);
	$audioscrobbler->query_param('sk', "");
	
	if ($response->is_success) {

		printf {*STDOUT} "created playlist:  %s\n\t%s\n", 
			$playlist_title,
			$playlist_description;

	} else {
		#print STDERR $response->status_line, "\n";
		my $error = XMLin($response->decoded_content);
		print $error->{error}{content} . "\n";
	}
}


sub trackLoveById($){

	my $tid = $_[0];

	my $xml = getXmlRecentTracks();
	my $tracks = $xml->{recenttracks}{track} ;
	my $idlist = mapTrackIds($tracks);

	###############

	my $idx = 0;

	while ( ((my $aidx, my $lsid) = each %$idlist) && ! $idx){
		if ($tid == $lsid) {
			$idx = $aidx;
		}
	}

	trackLove( 
		$tracks->[$idx]->{name},
		$tracks->[$idx]->{artist}{content},
	);
}

sub trackLove($$){

	(my $track, my $artist) = @_;

	$servargs{method}		= "track.love";
	$servargs{artist}		= $artist;
	$servargs{track}		= $track;
	$servargs{sk}			= $lfm_sk;


	getSignedMethod(\%servargs);

	my $response = $ua->post($audioscrobbler);
	$audioscrobbler->query_param('sk', "");
	
	if ($response->is_success) {

		printf {*STDOUT} "loved song: %s - %s\n", $artist, $track;

	} else {
		#print STDERR $response->status_line, "\n";
		my $error = XMLin($response->decoded_content);
		print $error->{error}{content} . "\n";
	}

}

sub getSignedMethod($){
	my $servargs	= $_[0];
	my $ms 			= "";

	foreach my $key (sort keys %$servargs){
		$ms 	.= encode_utf8($key)  	.	encode_utf8($servargs->{$key});
		$audioscrobbler->query_param($key, 	encode_utf8($servargs->{$key}));
	}
		$ms 	.= encode_utf8($secret); 
		$ms		 = md5_hex($ms);
		$audioscrobbler->query_param('api_sig', encode_utf8($ms));
	return $ms;
}

sub sortPlaylistByTitle($){
	my %xml = %{ $_[0] };
	my @ret = sort { lc($xml{$a}{title}) cmp lc($xml{$b}{title}) } keys %xml;
	return reverse @ret if ($OPT{'reverse'});
	return @ret;
}
sub sortPlaylistByTrack($){
	my %xml = %{ $_[0] };
	my @ret = sort { 
		my $left  = $xml{$a}{size} || 0;
		my $right = $xml{$b}{size} || 0;
		$left <=> $right
	} keys %xml;
	return reverse @ret if ($OPT{'reverse'});
	return @ret;
}
sub sortPlaylistById($){
	my %xml = %{$_[0]};
	my @ret = sort keys %xml;
	return reverse @ret if ($OPT{'reverse'});
	return @ret;
}
sub sortTracksByDate($) {
	my @in = @{$_[0]};
	my $now = time;
	my @ret = sort { 
		my $left = $in[$a]->{date}->{uts} || $now;
		my $right= $in[$b]->{date}->{uts} || $now;
		$left <=> $right 
	} keys @in;
	return reverse @ret if ($OPT{'reverse'});
	return @ret;
}

sub sortTracksByArtist($) {
	my @in = @{$_[0]};
	my @ret = sort { 
		my $left  = lc($in[$a]->{artist}{content}.$in[$a]->{name});
		my $right = lc($in[$b]->{artist}{content}.$in[$b]->{name});
		$left cmp $right 
	} keys @in;
	return reverse @ret if ($OPT{'reverse'});
	return @ret;
}

sub sortTracksByTitle($) {
	my @in = @{$_[0]};
	my @ret = sort { 
		my $left = lc($in[$a]->{name});
		my $right= lc($in[$b]->{name});
		$left cmp $right 
	} keys @in;
	return reverse @ret if ($OPT{'reverse'});
	return @ret;
}



#listRecentScrobbles();

#listPlaylists();

#source /home/jaroslav/src/bash/mpc-last/variables.sh
#curl "${SERVICE}?method=user.getplaylists&user=${LASTFM_USER}&api_key=${APIKEY}${JSON}" |\
#	grep -E '(<id>|<title>)' |\
#	tr -d '\n' |\
#	sed -e 's/<\/title>/\n/g' -e 's/<[^>]*>//g' |\
#	sed 's/^[\ ]*//' |\
#	cat -n

