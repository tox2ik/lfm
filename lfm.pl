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
use constant DEBUG			=> 1;

open(CONF, "<$ENV{'HOME'}/.mpc/last.fm") or die "Did you make a session key?: cant read: $!";
		my @conflines = <CONF>;
chomp( 	my $lfm_user = (split /:/, $conflines[0])[0]); 
chomp( 	my $lfm_sk 	= (split /:/, $conflines[0])[1]); 
close(CONF);


my $service				= 'http://ws.audioscrobbler.com/2.0/';
my $apikey 				= '1dfdc3a278e6bac5c76442532fcd6a05';
my $secret				= 'a70bafc9e39612700a2c1b61b5e0ab61';


my $httpTimeout			= 15;
my $terminal_encoding	= 'iso8859-1';
#my $terminal_encoding	= 'utf8';
#my $terminal_encoding	= 'koi8-r';
#my %servargs			= ();
#$servargs{api_key} 	= $apikey;
my	$ua 				= LWP::UserAgent->new;
	$ua->timeout( $httpTimeout);


## 
## FEEL FREE TO EDIT BELOW THIS LINE
##

my %cmds = (
	add 		=> 	{ api => 'playlist.addtrack', },
	create 		=>	{ api => 'playlist.create', },
	love		=>	{ api => 'track.love', },
	playlists	=>	{ api => "user.getplaylists", },
	tracks		=>	{ api => 'user.getrecenttracks', },
	tag			=>	{ mix => 'listtags', }
);


parseArguments();
binmode STDOUT, ":encoding($terminal_encoding)";

sub parseArguments {

	my %cmd_s2l = (
		a => 'add',
		c => 'create',
		l => 'love',
		p => 'playlists',
		t => 'tracks',
		T => 'tag',
	);

	# any - anything goes
	# int - integers
	# []  - list of possible values
	my %args = (
	 '-a' => {	add=>	'any', 
				love=>	'any',				
				tag=>	'any',
											}, 
	 '-A' => {	tag=>	'any'
	 										},
	 '-d' => {	create=>'any' 				}, 
	 '-l' => {	add =>		'int', 
		 		love=>		'int', 
				playlists=>	'int',
				tag=>		'int',
				tracks=>	'int',			
											}, 
	 '-ol'=> {  tag=>		'int',			},
	 '-n' => {	create=>	'any' 			}, 
	 '-p' => {	add=>		'int'			}, 
	'--p' => {	add=>		'any'			}, 
	 '-r' => {	love=>		'na',
		 		playlists=>	'na', 
				tag=>		'na',
				tracks=>	'na'	}, 
	 '-s' => {	playlists=>	['id','title','track'], 
		 		track=>		['id','track','artist'] }, 
	 '-t' => {	add=>		'int',
		 		love=>		'int',			
				tag=>		'int',
											},
	 '-ta' => {	tag=>		'any', 			},
	 '-tA' => {	tag=>		'any', 			},
	 '-tt' => {	tag=>		'any', 			},

	'--t' => { 	add=>	'any',
				love=>	'any',
				tag=>	'any',
											},

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
		my $argval		= utf8_value($ARGV[1], $terminal_encoding) || \\0;
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

	my %OPT = ();
	$OPT{sk} 			= $lfm_sk;
	$OPT{lfm_user}		= $lfm_user;
	$OPT{mix_method}	= $cmds{$cmd}{mix} 			|| undef;
	$OPT{api_method}	= $cmds{$cmd}{api} 			|| undef;
	$OPT{limit}			= $givenArgs{$cmd}{'-l'}	|| OUTPUT_LIMIT;
	$OPT{reverse} 		= $givenArgs{$cmd}{'-r'}	|| 0;
	$OPT{pid}			= $givenArgs{$cmd}{'-p'}	|| 0;
	$OPT{playlist}		= $givenArgs{$cmd}{'--p'}	|| "";
	$OPT{tid}			= $givenArgs{$cmd}{'-t'}	|| 0;
	$OPT{artist}		= $givenArgs{$cmd}{'-a'}	|| "";
	$OPT{album}			= $givenArgs{$cmd}{'-A'}	|| "";
	$OPT{track}			= $givenArgs{$cmd}{'--t'}	|| "";
	$OPT{name}			= $givenArgs{$cmd}{'-n'}	|| "";
	$OPT{description}	= $givenArgs{$cmd}{'-d'}	|| "";
	$OPT{order_by}		= $givenArgs{$cmd}{'-s'}	|| "";
	$OPT{output_limit}	= $givenArgs{$cmd}{'-ol'}	|| 20; # max 100 tags
	$OPT{tag_artist}	= $givenArgs{$cmd}{'-ta'}	|| "";
	$OPT{tag_album}		= $givenArgs{$cmd}{'-tA'}	|| "";
	$OPT{tag_track}		= $givenArgs{$cmd}{'-tt'}	|| "";
	
	#given ($cmd) {
	#when "add"		{ call_api20(\%OPT); }
	#when "create"	{ call_api20(\%OPT); }
	#when "love"		{ call_api20(\%OPT); }
	#when "playlists"{ call_api20(\%OPT); }
	#when "tracks"	{ call_api20(\%OPT); }
	#}

	call_api20(\%OPT);
	exit -1;
}

##
##  call the api
##

sub getXml_api20($){
	use Switch 'Perl 6';
	
	my %OPT 		= %{ $_[0] };
	my $method 		= $OPT{api_method};
	my %servargs	= ();
	my @xmlargs		= ();

	#print "getxml: $method\n";


	$servargs{api_key}	= $apikey;

	if (requires_authentication($method)){
		$servargs{sk}	= $lfm_sk;
	}

	given ($method){
		when "user.getrecenttracks" {

			$servargs{method}	= $method;
			$servargs{limit}	= $OPT{'limit'};
			$servargs{page}		= "1";
			$servargs{user}		= $lfm_user;
			#$servargs{from}	= `epoch`;
			#$servargs{to}		= `epoch`;

			@xmlargs = (keyattr => {}, forcearray => 0);
		}

		when "user.getplaylists" {

			$servargs{method}	= $method;
			$servargs{user}		= $lfm_user;
			$servargs{page}		= "1";
			#$servargs{from}        = `epoch`;
			#$servargs{to}          = `epoch`;

			@xmlargs = (forcearray=>0);
		}
		when "artist.gettoptags" {
			$servargs{method}	= $method;
			$servargs{artist}	= $OPT{'artist'};
			$servargs{autocorrect} = 1;
			#$mbid				= $OPT{mbid}
		}

		when "album.gettoptags" {
			$servargs{method}	= $method;
			$servargs{artist}	= $OPT{'artist'};
			$servargs{album}	= $OPT{'album'};
			$servargs{autocorrect} = 1;
			#$mbid				= $OPT{mbid}

		}
		when "track.gettoptags" {
			$servargs{method}	= $method;
			$servargs{artist}	= $OPT{'artist'};
			$servargs{track}	= $OPT{'track'};
			$servargs{autocorrect} = 1;
			#$mbid				= $OPT{mbid}
		}

		when "artist.gettags" {
			$servargs{method}	= $method;
			$servargs{artist}	= $OPT{'artist'};
			$servargs{autocorrect} = 1;
			#$mbid				= $OPT{mbid}
		}

		when "album.gettags" {
			$servargs{method}	= $method;
			$servargs{artist}	= $OPT{'artist'};
			$servargs{album}	= $OPT{'album'};
			$servargs{autocorrect} = 1;
			#$mbid				= $OPT{mbid}

		}
		when "track.gettags" {
			$servargs{method}	= $method;
			$servargs{artist}	= $OPT{'artist'};
			$servargs{track}	= $OPT{'track'};
			$servargs{autocorrect} = 1;
			#$mbid				= $OPT{mbid}
		}

		default {
			printError("Routine for fetching xml ($method) is not defined ");
		}
	}

	my $response = getResponse(\%servargs, 'utf8');

	#print Dumper($response->decoded_content);

	if ($response->is_success) {
		#print Dumper( XMLin(($response->decoded_content, @xmlargs)) );
		return XMLin(($response->decoded_content, @xmlargs));
	}

	return -1;
}



sub call_api20($);
sub call_api20($){
	use Switch 'Perl 6';
	my %OPT = %{ $_[0] };
	my %servargs = ();

	my $method 		= $OPT{api_method} || $OPT{mix_method};

	$servargs{method}	= $method;
	$servargs{api_key}	= $apikey;

	if (requires_authentication($method)){
		$servargs{sk}	= $lfm_sk;
	}



	my %opt_recenttracks = (
		api_method	=> $cmds{tracks}{api},
		limit		=> $OPT{limit},
		page		=> $OPT{page} || 1,
		user		=> $OPT{user} || $lfm_user,
		#to			=> $OPT{epoch_to} || 0,
		#from		=> $OPT{epoch_frome} || 0,
	);
	my %opt_playlists = (
		api_method	=> $cmds{playlists}{api},
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


	given ($servargs{method}) {
		when "track.love" { 	

			if ($OPT{reverse} == 1){
				$servargs{method} = 'track.unlove';
			}
		}

		when "playlist.create" {

			$servargs{title}		= $OPT{name};
			$servargs{description}	= $OPT{description};
		}

		when "playlist.addtrack" {
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
		}

		when "user.getplaylists" {

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
		}

		when "user.getrecenttracks" {
			my $maxa = 0;
			my $maxt = 0;
			my $maxid = 2 +(length $OPT{'limit'});
		
			#my $xmlresponse = getXmlRecentTracks();
			my $xml		= getXml_api20({
					api_method	=> $cmds{tracks}{api},
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
		}
		when "listtags" {
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
		}

		when "artist.addtags" { $servargs{tags}	= $OPT{tag_artist}; }
		when  "album.addtags" { $servargs{tags}	= $OPT{tag_album}; }
		when  "track.addtags" { $servargs{tags}	= $OPT{tag_track}; }
		when "artist.removetag" { $servargs{tag}	= $OPT{tag_artist}; }
		when  "album.removetag" { $servargs{tag}	= $OPT{tag_album}; }
		when  "track.removetag" { $servargs{tag}	= $OPT{tag_track}; }

		default { printError(
			(caller(0))[3].": Routine not defined for $OPT{api_method}");
			exit 1;
	}} 

	my $response = getResponse(\%servargs, $terminal_encoding);

	if ($response->is_success) {
		my $confirmation = "";
		given ($servargs{method}) {
			when "track.love" { 
				$confirmation = "loved song: $servargs{artist} - $servargs{track}";
			}
			when "track.unlove" { 
				$confirmation = 
				"unloved song: $servargs{artist} - $servargs{track}";
			}
			when "playlist.create" { 
				$confirmation = 
				"created playlist: $OPT{name}\n\t$OPT{description}";
			}

			when "playlist.addtrack" {
				$confirmation = 
				"added $OPT{artist} - $OPT{track} to $OPT{playlist}\n";
			} 

			when "artist.addtags" {
				$confirmation = 
				"tagged $OPT{artist} with $OPT{tag_artist}\n";
			} 

			when "album.addtags" {
				$confirmation = 
				"tagged $OPT{album} with $OPT{tag_album}\n";
			} 
			when "track.addtags" {
				$confirmation = 
				"tagged $OPT{track} with $OPT{tag_track}\n";
			} 
		}	
		printf {*STDOUT} "$confirmation\n";
		return 0;
	}
}

##
## HELPERS 
##

sub getResponse($$){
	my %servargs;
	my $response;
	my $incoding;
	my $audioscrobbler	= URI->new($service);

	printError((caller(0))[3].": please pass a hash reference")
	if (ref $_[0] ne 'HASH');

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

sub mapTrackIds($$){

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
	.   add        -p { pID | name } -t { tID | TITLE } -a NAME
	.   create     -d DESCRIPTION -n NAME
	.   love       [ -r (unlove)   ] -t { tID | TITLE } -a NAME
	.   playlists  [ -l n] [ -s { id | title | track  }]
	.   tracks     [ -l n] [ -s { id | title | artist }]
	.   tag        -a artist -A album -t tID --t track -ls
	.
	. general options
	.   -r                  reverse sort order (or unlove)
	.   -l <N>              limit output to N lines
	.   -s                  sort output by id, title or artist
EOH
	;
	$help =~ s/^\t+\.//gm;
	$help =~ s/\$0/$0/;
	$help .= "\nERROR:\n$error \n" unless (length $error <= 0);
	print STDERR $help;
	exit;
}
