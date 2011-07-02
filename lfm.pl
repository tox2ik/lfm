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



my $httpTimeout		= 15;
my $terminal_encoding	= 'utf8';
my %servargs		= ();
my	$ua 		= LWP::UserAgent->new;
	$ua->agent('mpclast/0.1');
	$ua->timeout($httpTimeout);
my $audioscrobbler	= URI->new($service);

my $xs 			= new XML::Simple(
						KeyAttr => [ ],
					);


my $OPT_limit			= 14;
my $OPT_sort_reverse 	= 0;
my $OPT_plist_order		= \&sortPlaylistByTitle;
my $OPT_tracks_order	= \&sortTracksByDate;
my $OPT_artist			= "";
my $OPT_track			= "";
my $OPT_pid				= 0;
my $OPT_tid				= 0;


$servargs{api_key} = $apikey;



binmode STDOUT, ":encoding($terminal_encoding)";


#print Dumper(getXmlRecentTracks());
#exit 1;

parseArguments();

## 
## FEEL FREE TO EDIT BELOW THIS LINE
##

sub parseArguments {
	my %valid = (
		p => \&listPlaylists, 
		playlists => \&listPlaylists, 

		t => \&listRecentScrobbles,
		recent => \&listRecentScrobbles,
		
		a => { 	long => \&addTrackToPlaylist, 
				short=> \&addTrackToPlaylistById,},
		add => {long => \&addTrackToPlaylist, 
				short=> \&addTrackToPlaylistById,},
	);
	my $command = shift @ARGV || printHelp();

	my $playlists = $command eq "p" || $command eq "playlists";
	my $tracks = $command eq "t" || $command eq "tracks";
	my $add = $command eq "a" || $command eq "add";

	my $i = $#{ARGV};
	while ($i>=0) {
		#print "i: $i\n";
		$a = $ARGV[0]; shift @ARGV; $i--;
		#print "a: $a\n";

		if ($a eq "-s") {
			$i--;
			my $b = shift @ARGV || printHelp("Bad arguments, -s needs a value"); 

			if 		($playlists) {

				if		($b eq "id")   {$OPT_plist_order=\&sortPlaylistById;} 
				elsif	($b eq "track"){$OPT_plist_order=\&sortPlaylistByTitle;}
				else { printHelp("Bad -s option for command $command"); }

			} elsif ($tracks) {

				if		($b eq "id")   {$OPT_tracks_order=\&sortTracksByDate;} 
				elsif	($b eq "track"){$OPT_tracks_order=\&sortTracksByTitle;}
				elsif  ($b eq "artist"){$OPT_tracks_order=\&sortTracksByArtist;}
				else { printHelp("Bad -s option for command $command"); }
			}
		} elsif ($a eq "-p") {		$i--;
			my $b = shift @ARGV 	|| printHelp("Bad arguments, -p needs a value, see the playlists command"); 
			$OPT_pid = $b;
		} elsif ($a eq "-t") {		$i--;
			my $b = shift @ARGV 	|| printHelp("Bad arguments, -t needs a value, see the tracks command"); 
			$OPT_tid = int $b;
		} elsif ($a eq "-track") {	$i--;
			my $b = shift @ARGV 	|| printHelp("Bad arguments, -track needs a value"); 
			$OPT_track = $b;
		} elsif ($a eq "-artist") {	$i--;
			my $b = shift @ARGV 	|| printHelp("Bad arguments, -artist needs a value"); 
			$OPT_artist = $b;

		} elsif ($a eq "-l") {		$i--;
			my $val = shift @ARGV 	|| printHelp("Bad -l value ") ; 
			$OPT_limit = int $val; 
			$OPT_limit > 0 || printHelp("Bad -l value");
		} elsif ($a eq "-r") { 
			$OPT_sort_reverse = 1;
		}


	}

	foreach (keys %valid){
		if ($_ eq $command) {
			if ($add && $OPT_tid != 0) {
				$valid{$command}{short}->($OPT_tid, $OPT_pid);
			} elsif ($add) {
				$valid{$command}{long}->($OPT_track, $OPT_artist, $OPT_pid);
			} else {
				$valid{$command}->();
			}
			exit 0;
		}
	}
}


sub printHelp {

	(my $help =<< 'EOH');

	.usage: $0: <command> [options]
	. where command is one of 
	.  p    playlists       list available (created) playlists
	.  t    tracks          list recently scrobbled tracks
	.  a    add             add a song to one of your lists
	.
	. and options is one or several of
	.  -s <id|track|artist>	sort output by id, title or artist
	.  -l <N>               limit output to N lines
	.  -r                   reverse sort order
	.  -track               song title (e.g. It Takes Two To Tango)
	.  -artist              performer alias (e.g. Louis Armstrong)
	.  -t                   track ID
	.  -p                   playlist ID or name
	.
	. applicability of options:
	.  playlists: -s <id | track>
	.  tracks:    -s <id | title | artist>
	.  add:       -p <pID | name> <-t tID | -track TITLE -artist NAME>
	.  tracks,  
	.  playlists: -l, -r

EOH
	$help =~ s/^\t+\.//gm;
	$help =~ s/\$0/$0/;
	print $help;

	my $error =  $_[0] ||  "";

	print "ERROR: $_[0] \n " unless (length $error <= 0);
	exit 1;
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

	addTrackToPlaylist( 
		$tracks->[$idx]->{name},
		$tracks->[$idx]->{artist}{content},
		$plid
	);
}

sub addTrackToPlaylist($$$) {
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


	# fill in parameters

	$servargs{method}		= "playlist.addtrack";
	$servargs{sk}			= $lfm_sk;
	$servargs{artist}		= $artist;
	$servargs{track}		= $track;
	$servargs{playlistID}	= $lfm_plid;

	# sign the method

	my $ms = "";
	foreach my $key (sort keys %servargs){
		$ms .= encode_utf8($key) . encode_utf8($servargs{$key});
		$audioscrobbler->query_param($key, encode_utf8($servargs{$key}));
	}
		$ms .= encode_utf8($secret); 
		$ms = md5_hex($ms);
		$audioscrobbler->query_param('api_sig', encode_utf8($ms));

	# post the request

	my $response = $ua->post($audioscrobbler);

	if ($response->is_success) {

		printf {*STDOUT} "added %s - %s to %s\n", $artist, $track,
				$pls_ref->{$lfm_plid}{title};


	} else {
		#print STDERR $response->status_line, "\n";
		my $error = XMLin($response->decoded_content);
		print $error->{error}{content} . "\n";
	}
}

sub createPlaylist(){
#	playlist.create
#	Create a Last.fm playlist on behalf of a user
#	Params
#	title (Optional) : Title for the playlist
#	description (Optional) : Description for the playlist
#	api_key (Required) : A Last.fm API key.
#	api_sig (Required) : A Last.fm method signature. See authentication for more information.
#	sk (Required) : A session key generated by authenticating a user via the authenticatio
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

