#!/usr/bin/perl -w
use warnings;
use strict;

use English;
#use File::Basename;
use LWP::UserAgent;
use URI::QueryParam;
use List::Util qw[min max];
use Encode;
use XML::Simple;
use Digest::MD5 qw(md5_hex);
use Tie::File; 

use Data::Dumper;
#$Data::Dumper::Indent = 1;
#$Data::Dumper::Pair = " => ";

#use Term::ANSIColor qw(:constants);
#$Term::ANSIColor::AUTORESET = 1;


my $conf_path 	= "$ENV{'HOME'}/.mpc/last.fm";

open(CONF, "<$conf_path") or die "Did you make a session key?: cant read: $!";
my @conflines = <CONF>;

my $service	= 'http://ws.audioscrobbler.com/2.0/';
my $apikey 	= '1dfdc3a278e6bac5c76442532fcd6a05';
my $secret 	= 'a70bafc9e39612700a2c1b61b5e0ab61';
chomp( my $lfm_user = (split /:/, $conflines[0])[0]); 
chomp( my $lfm_sk 	= (split /:/, $conflines[0])[1]); 

close(CONF);


use constant WIDTH_ARTIST	=> 43;
use constant WIDTH_SONG		=> 23;



my $httpTimeout			= 15;
my $terminal_encoding	= 'utf8';
my %servargs			= ();
   $servargs{api_key} 	= $apikey;
my	$ua 				= LWP::UserAgent->new;
	$ua->timeout(
		$httpTimeout);
my $audioscrobbler		= URI->new($service);

#my $xs					= new XML::Simple( KeyAttr => [ ],);

my $OPT_limit			= 14;
my $OPT_sort_reverse 	= 0;
my $OPT_plist_order		= \&sortPlaylistByTitle;
my $OPT_tracks_order	= \&sortTracksByDate;
my $OPT_artist			= "";
my $OPT_track			= "";
my $OPT_pid				= 0;
my $OPT_tid				= 0;
my $OPT_description		= "";
my $OPT_name			= "";



binmode STDOUT, ":encoding($terminal_encoding)";


#print Dumper(getXmlRecentTracks());
#exit 1;

parseArguments();

## 
## FEEL FREE TO EDIT BELOW THIS LINE
##

# TODO generalize argument checking and input validation

sub parseArguments {
	my $argc = @ARGV;
	my %cmds = (
		add 		=> { long 	=> \&playlist_addTrack, 
						 short 	=> \&addTrackToPlaylistById,},
		create 		=> \&createPlaylist, 
		love		=> { long	=> \&trackLove,
						 short	=> \&trackLoveById,
						 long_r => \&trackUnLove,
						 short_r=> \&trackUnLoveById, },
		playlists	=> \&listPlaylists, 
		tracks		=> \&listRecentScrobbles,
	);
	my %cmd_s2l = (
		a => 'add',
		c => 'create',
		l => 'love',
		p => 'playlists',
		t => 'tracks',
	);

	$cmds{a} = \$cmds{$cmd_s2l{a}};
	$cmds{c} = \$cmds{$cmd_s2l{c}};
	$cmds{l} = \$cmds{$cmd_s2l{l}};
	$cmds{p} = \$cmds{$cmd_s2l{p}};
	$cmds{t} = \$cmds{$cmd_s2l{t}};

	# any - anything goes
	# int - integers
	# []  - list of possible values
	my %args = (
	 '-a' => { add=>'any', love=>'any',  }, 
	 '-d' => { create=>'any' }, 
	 '-l' => { playlists=>'int', tracks=>'int' }, 
	 '-n' => { create=>'any' }, 
	 '-p' => { add=>'int'}, 
	'--p' => { add=>'any'}, 
	 '-r' => { love=>'', playlists=>'', tracks=>''  }, 
	 '-s' => { playlists=>['id','track'], track=>['id','track','artist'] }, 
	 '-t' => { add=>'int', 	love=>'int' },
	'--t' => { add=>'any', 	love=>'any' },
	);

	my %givenArgs = ();
	my $consumed = 0;
	my $cmd = $ARGV[0] || '^$'; 
	   $cmd = $cmd_s2l{$cmd} || $cmd;
	print "cmd: $cmd \n";

	unless (grep {/^$cmd$/} (keys %cmds)) {
		printHelp("command is one of: @{[sort keys %cmds]}");
	}

	sub invalid($$){ printHelp("$_[0] does not take $_[1]"); }

	print "args: $argc \n ";
	while ($argc > 1) {
		$a = splice @ARGV, 1, 1;
		$argc--;
		print "a: $a \n";
		#
		# general strategy: 
		#  check that -arg is in %args
		#    find out what kind of value -arg takes (int/any/list)
		#      verify that -arg does operate in given mode (add/love/playlists)
		#


		if (grep {/$a/} (keys %args)) {
			foreach my $mode (keys %{ $args{$a}} ) {
				my $a_ref 	= \$args{$a}{$mode};
				my $ga_ref	= \$givenArgs{$a}{$mode};
				my @argmodes= keys %{$args{$a}};
				my $argval	= $ARGV[1] || '^$';

				$consumed = 1;

				if	($$a_ref eq 'any') {

					invalid($cmd,$a) unless (grep {/$cmd/} @argmodes);
						$$ga_ref = $argval;

					#if (grep {/$cmd/} @argmodes){
					#	$$ga_ref = $argval;
					#} else { invalid($cmd,$a);}

				} elsif	($$a_ref eq 'int') {
					invalid($cmd,$a) unless (grep {/$cmd/} @argmodes);
						($$ga_ref = int $argval) != 0 ||   
							printHelp("$a takes an int > 0"); 

					#if (grep {/$cmd/} @argmodes){
					#	($$ga_ref = int $argval) != 0 ||   
					#		printHelp("$a takes an int > 0"); 
					#} else {printHelp(
					#		"$cmd does not take $a");
					#}
				} elsif	(ref $$a_ref eq 'ARRAY' ) {
					invalid($cmd,$a) unless (grep {/$cmd/} @argmodes);

					printHelp("$mode $a must be one of: @{$$a_ref}") 
						unless (grep {/$argval/} @{$$a_ref} );
							$$ga_ref = $argval; 

					#if (grep {/$cmd/} @argmodes){
					#	if (grep {/$argval/} @{$$a_ref} ){ # value in accepted list? 
					#		$$ga_ref = $argval; 
					#	} else { 
					#		if ( $cmd eq $mode ){ printHelp(
					#			"$mode $a must be one of: @{$$a_ref}");
					#		} elsif ($cmd ne $mode ){ printHelp(
					#			"$cmd does not take $a");
					#		}
					#	}
					#} else {printHelp(
					#		"$cmd does not take $a");
					#}
				} else {
					my $type =  ref $args{$a}{$mode} || "none for $mode";
					print "$a has type $type \n";
					$consumed = 0;
				}
			}
		} else {
			printHelp("Invalid argument: $a") 
		}
		if ($consumed) { 
			#shift @ARGV;
			splice(@ARGV, 1, 1);
			$argc--;
			$consumed = 0;
		}
	}


	#print Dumper( %givenArgs);
	foreach my $arg (keys %givenArgs) {
		foreach my $value (keys %{$givenArgs{$arg}}){
			print "$arg - $value - $givenArgs{$arg}{$value} \n";
		}
	}
	

	#foreach (keys %valid){
	#	if ($_ eq $cmd) {
	#		if ($add && $OPT_tid != 0) {
	#			$valid{$cmd}{short}->($OPT_tid, $OPT_pid);
	#		} elsif ($add) {
	#			$valid{$cmd}{long}->($OPT_track, $OPT_artist, $OPT_pid);

	#		} elsif ($love && $OPT_tid != 0) {
	#			$valid{$cmd}{short}->($OPT_tid);
	#		} elsif ($love && $OPT_tid != 0 && $OPT_sort_reverse == 1) {
	#			$valid{$cmd}{short_r}->($OPT_tid);
	#		} elsif ($love) {
	#			$valid{$cmd}{long}->($OPT_track, $OPT_artist);
	#		} elsif ($love && $OPT_sort_reverse == 1) {
	#			$valid{$cmd}{long_r}->($OPT_track, $OPT_artist);


	#		} elsif ($create) {
	#			$valid{$cmd}->($OPT_name, $OPT_description);


	#		} else {
	#			$valid{$cmd}->();
	#		}
	#		exit 0;
	#	}
	#}

	exit 1;

		#if ($a eq "-s") {
		#	$argc--;
		#	my $b = shift @ARGV || printHelp("Bad arguments, -s needs a value"); 

		#	if 		($playlists) {

		#		if		($b eq "id")   {$OPT_plist_order=\&sortPlaylistById;} 
		#		elsif	($b eq "track"){$OPT_plist_order=\&sortPlaylistByTitle;}
		#		else { printHelp("Bad -s option for cmd $cmd"); }

		#	} elsif ($tracks) {

		#		if		($b eq "id")   {$OPT_tracks_order=\&sortTracksByDate;} 
		#		elsif	($b eq "track"){$OPT_tracks_order=\&sortTracksByTitle;}
		#		elsif  ($b eq "artist"){$OPT_tracks_order=\&sortTracksByArtist;}
		#		else { printHelp("Bad -s option for cmd $cmd"); }
		#	}

		#} elsif ($a eq "-p") {		$argc--;
		#	my $b = shift @ARGV 	|| printHelp("Bad arguments, -p needs a value, see the playlists command"); 
		#	$OPT_pid = $b;
		#} elsif ($a eq "-t") {		$argc--;
		#	my $b = shift @ARGV 	|| printHelp("Bad arguments, -t needs a value, see the tracks command"); 
		#	$OPT_tid = int $b;
		#} elsif ($a eq "-track") {	$argc--;
		#	my $b = shift @ARGV 	|| printHelp("Bad arguments, -track needs a value"); 
		#	$OPT_track = $b;
		#} elsif ($a eq "-artist") {	$argc--;
		#	my $b = shift @ARGV 	|| printHelp("Bad arguments, -artist needs a value"); 
		#	$OPT_artist = $b;

		#} elsif ($a eq "-n") {	$argc--;
		#	my $b = shift @ARGV 	|| printHelp("Bad arguments, supply a playlist name with -n"); 
		#	$OPT_name = $b;
		#} elsif ($a eq "-d") {	$argc--;
		#	my $b = shift @ARGV 	|| printHelp("Bad arguments, optional parameter -d needs a value "); 
		#	$OPT_description = $b;

		#} elsif ($a eq "-l") {		$argc--;
		#	my $val = shift @ARGV 	|| printHelp("Bad -l value ") ; 
		#	$OPT_limit = int $val; 
		#	$OPT_limit > 0 || printHelp("Bad -l value");
		#	# TODO make -l 1 work 
		#} elsif ($a eq "-r") { 
		#	$OPT_sort_reverse = 1;
		#}

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
	.   playlists  [ -l n] [ -s { id | track } ]
	.   tracks     [ -l n] [ -s { id | title | artist }
	.
	. general options
	.   -r                  reverse sort order (or unlove)
	.   -l <N>              limit output to N lines
	.   -s                  sort output by id, title or artist
EOH
	$help =~ s/^\t+\.//gm;
	$help =~ s/\$0/$0/;
	$help .= "\nERROR: $error \n" unless (length $error <= 0);
	print $help;
	exit -1;
}


sub getXmlRecentTracks {

	$servargs{method}	= "user.getrecenttracks";
	$servargs{limit}	= $OPT_limit;
	$servargs{page}		= "1";
	$servargs{user}		= $lfm_user;
	#$servargs{from}	= `epoch`;
	#$servargs{to}		= `epoch`;

	foreach my $param (sort keys %servargs){
		$audioscrobbler->query_param($param, $servargs{$param}); }

	my $response = $ua->get($audioscrobbler);

	if ($response->is_success) {
		#print Dumper($response->decoded_content);
		return XMLin(
				$response->decoded_content, 
				keyattr => {  },
				#keyattr => { track=>'date' },
				forcearray => 0,
		);
	} else {
		print STDERR $response->status_line, "\n";
	}
}

sub getXmlRecentTracksAlt {

	$servargs{method}	= "user.getrecenttracks";
	$servargs{limit}	= $OPT_limit;
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
		if ($OPT_sort_reverse){
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
	my $maxid = 1 +( int length $OPT_limit) ;

	my $xmlresponse = getXmlRecentTracks();
	my $tracks = $xmlresponse->{recenttracks}{track} ;
	my @tracks = @{ $tracks };
	my @sorted = $OPT_tracks_order->($tracks);

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


	printf {*STDOUT} "% ".$maxid."s  %02s:%02s % ".$maxa."s - %- ".$maxt."s\n", 
			"tID", "hh", "mm", "Artist", "Track";

	foreach (@sorted){

		my $trk		= $tracks[$_];
		my $epoch	= $trk->{date}->{uts} || time;
		my $name 	= $trk->{name};
		my $artist	= $trk->{artist}->{content};

		#my ($sec, $min, $hour, $day,$month,$year) = 
		#	(localtime($epoch))[0,1,2,3,4,5,6]; 
		my ($min,$hour) = (localtime($epoch))[1,2] ;

		printf {*STDOUT} "% ".$maxid."d  %02d:%02d % ".$maxa."s - %- ".$maxt."s\n", 
		#$idlist->{$_}, $hour, $min, $artist, $name;
			$_ + 1, $hour, $min, $artist, $name;
	}
}


sub mapPlaylistIds($){
	my $xmlref	= $_[0];
	my $len		= keys %{ $xmlref };
	my %idlist	= ();

	my $global_so = $OPT_sort_reverse;
	$OPT_sort_reverse = 1;
	foreach my $id ( sortPlaylistById( $xmlref )) { 
		$idlist{$id} = $len--;
	}
	$OPT_sort_reverse = $global_so;
	return \%idlist
}

sub listPlaylists {

	my $xml 	= getXmlPlaylists();
	my $pls_ref	= $xml->{playlists}->{playlist};
	my %pls		= %{ $pls_ref };
	my $idlist  = mapPlaylistIds($pls_ref);

	printf {*STDOUT}  "% 9s = %s \n", "ID", "Playlist" ; 

	foreach my $id ( $OPT_plist_order->( $pls_ref )) { 
		printf {*STDOUT}  "% 9s = %s \n", $idlist->{$id}, $pls{$id}{title} ; 
	}
}

sub addTrackToPlaylistById($$) {

	printHelp("missing parameters") if grep( /""|0/, @_);

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

	playlist_addTrack( 
		$tracks->[$idx]->{name},
		$tracks->[$idx]->{artist}{content},
		$plid
	);
}

sub playlist_addTrack($$$) {

	printHelp("missing parameters") if grep( /""|0/, @_);

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

	rintHelp("No such playlist") if ($plid =~ m/0|^$/ );
	printHelp("Bad artist name") if ($artist =~ m/^$/ );
	printHelp("Bad track name") if ($track =~ m/^$/ );


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


	} else {
		print STDERR $response->status_line, "\n";
		my $error = XMLin($response->decoded_content);
		print $error->{error}{content} . "\n";
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
	return reverse @ret if ($OPT_sort_reverse);
	return @ret;
}
sub sortPlaylistById($){
	my %xml = %{$_[0]};
	my @ret = sort keys %xml;
	return reverse @ret if ($OPT_sort_reverse);
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
	return reverse @ret if ($OPT_sort_reverse);
	return @ret;
}
sub sortTracksByArtist($) {
	my @in = @{$_[0]};
	my @ret = sort { 
		my $left  = lc($in[$a]->{artist}{content}.$in[$a]->{name});
		my $right = lc($in[$b]->{artist}{content}.$in[$b]->{name});
		$left cmp $right 
	} keys @in;
	return reverse @ret if ($OPT_sort_reverse);
	return @ret;
}

sub sortTracksByTitle($) {
	my @in = @{$_[0]};
	my @ret = sort { 
		my $left = lc($in[$a]->{name});
		my $right= lc($in[$b]->{name});
		$left cmp $right 
	} keys @in;
	return reverse @ret if ($OPT_sort_reverse);
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

