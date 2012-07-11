
package Hum::Chromoview::Utils;

### Author: ck1@sanger.ac.uk


use vars qw{ @ISA @EXPORT_OK };
use strict;
use warnings;
use DBI;
use Net::Netrc;
use Hum::Chromoview::ChromoSQL;
use Hum::Sort ('ace_sort');
use Hum::Conf qw{CHROMODB_CONNECTION LOUTRE_CONNECTION};
use Hum::Submission 'prepare_statement';
use Hum::Tracking ('prepare_track_statement');
use URI::Escape;
use Config::IniFiles;
#use CGI;
#use CGI::Carp qw(warningsToBrowser fatalsToBrowser);

@ISA = ('Exporter');
@EXPORT_OK = qw(
				is_local
                authorize
                check_for_crossmatch_errors_by_accSv
                concat_js_params
                datetime2unixTime
                extra_footer_browsers
                fetch_seq_region_id_by_accession
                get_DNA_from_ftpghost
                get_TPF_modtime
                get_all_current_TPFs
                get_chromoDB_handle
                get_id_tpftargets_by_acc_sv
                get_id_tpftargets_by_seq_region_id
                get_latest_TPF_update_of_clone
                get_latest_clone_entries_with_overlap_of_assembly
                get_latest_clone_entrydate_of_TPF
                get_latest_overlap_statusdate_of_TPF
                get_loutredbh_from_species
                get_mysql_datetime
                get_script_root
                get_seq_len_by_acc_sv
                get_species_chr_subregion_from_id_tpftarget
                get_yyyymmdd
				google_analytics
                make_hmenus
                make_search_box
                make_table_row
                phase_2_status
                store_failed_overlap_pairs
                unixtime2YYYYMMDD
                unixtime2datetime
                unixtime2tpftime
				make_error_email
               );

sub make_error_email {
	return q{<b>Problems with Chromoview?</b> Email <a href="mailto:grc-help@sanger.ac.uk">grc-help@sanger.ac.uk</a>};
}
			   
sub google_analytics {

	my $google_code = <<BLOCK;

  var _gaq = _gaq || [];
  _gaq.push(['_setAccount', 'UA-22455456-1']);
  _gaq.push(['_trackPageview']);

  (function() {
    var ga = document.createElement('script'); ga.type = 'text/javascript'; ga.async = true;
    ga.src = ('https:' == document.location.protocol ? 'https://ssl' : 'http://www') + '.google-analytics.com/ga.js';
    var s = document.getElementsByTagName('script')[0]; s.parentNode.insertBefore(ga, s);
  })();

BLOCK

	return $google_code;

}

sub is_local {
	if($ENV{HTTP_CLIENTREALM} =~/sanger/) {
		return 1;
	}
	else {
		return 0;
	}
}

sub store_failed_overlap_pairs {
  my ($qry_accSv, $hit_accSv, $errmsg) = @_;

  my $dba = get_chromoDB_handle();

  my (@srids, $wanted_itt);

  foreach ($qry_accSv, $hit_accSv) {
    my $srid = fetch_seq_region_id_by_accession($_);
    push(@srids, $srid);
    my $itts = get_id_tpftargets_by_seq_region_id($srid);

    foreach my $itt ( @$itts ){
      my ($species, $chr, $subregion ) = get_species_chr_subregion_from_id_tpftarget($itt);
      if ( !$wanted_itt and $species and !$subregion ) {
        $wanted_itt = $itt;
      }
    }
  }

  #  <<ottroot@otterpipe2 chromoDB>> desc tpf_failed_overlap_pairs;
  #+--------------+------------------+------+-----+---------+----------------+
  #| Field        | Type             | Null | Key | Default | Extra          |
  #+--------------+------------------+------+-----+---------+----------------+
  #| err_id       | int(10) unsigned |      | PRI | NULL    | auto_increment |
  #| id_tpftarget | int(10) unsigned |      |     | 0       |                |
  #| srid_a       | int(10)          |      | MUL | 0       |                |
  #| srid_b       | int(10)          |      |     | 0       |                |
  #+--------------+------------------+------+-----+---------+----------------+

  #<<ottroot@otterpipe2 chromoDB>> desc tpf_overlap_errors
  #    -> ;
  #+---------+---------+------+-----+---------+-------+
  #| Field   | Type    | Null | Key | Default | Extra |
  #+---------+---------+------+-----+---------+-------+
  #| err_id  | int(10) |      | PRI | 0       |       |
  #| message | text    | YES  |     | NULL    |       |
  #+---------+---------+------+-----+---------+-------+

  # $wanted_itt is set only for main chromosome TPF
  if ( $wanted_itt ){
    my $srids = join(', ', @srids);

    my $insert_a = $dba->prepare(qq{REPLACE INTO tpf_failed_overlap_pairs VALUES(?, $wanted_itt, $srids)});
    $insert_a->execute();

    my $lastID = $dba->last_insert_id(undef, undef, undef, undef, undef);

    my $insert_b = $dba->prepare(qq{INSERT INTO tpf_overlap_errors VALUES($lastID, "$errmsg")});
    $insert_b->execute();
  }
}

sub check_for_crossmatch_errors_by_accSv {
  my ( $accSv ) = @_;

  my $chromo_dbh = get_chromoDB_handle();
  my $qry = $chromo_dbh->prepare(qq{SELECT LEFT(e.message, 1)
                                    FROM tpf_info i, tpf_failed_overlap_pairs p, tpf_overlap_errors e, seq_region sra, seq_region srb
                                    WHERE i.id_tpftarget=p.id_tpftarget
                                    AND p.err_id=e.err_id
                                    AND p.srid_a=sra.seq_region_id
                                    AND p.srid_b=srb.seq_region_id
                                    AND sra.name = ?
                                  });
  $qry->execute("$accSv");

  if ( my $err = $qry->fetchrow ){
    $err = $err eq 'c' ? 'Job terminated: crossmatch used up virtual memory set for finding end-overlap' : 
                         'No alignment found between clones';
    return $err;
  }
}

sub get_seq_len_by_acc_sv {
  my($acc_sv) = @_;
  my $dba = get_chromoDB_handle();
  my $qry = $dba->prepare(qq{SELECT length FROM seq_region WHERE name = ?});
  $qry->execute($acc_sv);
  return $qry->fetchrow;
}

{
	my $qry;

	sub get_id_tpftargets_by_seq_region_id {
	  my ($srId) = @_;
	  my $dba = get_chromoDB_handle();
	  $qry ||= $dba->prepare(q{SELECT name FROM seq_region WHERE seq_region_id = ?});
	  $qry->execute($srId);
	  my $accSv = $qry->fetchrow;
	  if ( defined $accSv and $accSv =~ /\./ ){
    	return get_id_tpftargets_by_acc_sv( split(/\./, $accSv) );
	  }

	  return 0;
	}
}

{
	my $qry;

	sub get_id_tpftargets_by_acc_sv {

	  my ($acc, $sv) = @_;
	  $qry ||= prepare_track_statement(qq{
                                    	   SELECT DISTINCT tt.id_tpftarget
                                    	   FROM sequence s, clone_sequence cs, tpf_row tr, tpf t, tpf_target tt
                                    	   WHERE t.iscurrent=1
                                    	   AND s.accession=?
                                    	   AND s.sv=?
                                    	   AND s.id_sequence=cs.id_sequence
                                    	   AND cs.clonename=tr.clonename
                                    	   AND tr.id_tpf=t.id_tpf
                                    	   AND t.id_tpftarget=tt.id_tpftarget
                                    	 });
	  $qry->execute($acc, $sv);

	  my $id_tpftargets = [];
	  while ( my $id = $qry->fetchrow ){
    	push(@$id_tpftargets, $id);
	  }

	  return $id_tpftargets;

	}
}

sub fetch_seq_region_id_by_accession {
  my ($acc) = @_;

  my $dba = get_chromoDB_handle();
  my $qry = $dba->prepare(qq{SELECT seq_region_id
                             FROM seq_region
                             WHERE name LIKE ?
                             ORDER BY seq_region_id
                             DESC LIMIT 1});
  $qry->execute("$acc%");

  return $qry->fetchrow;
}

sub authorize {

  my $sanger_user = shift;
  my $user_group = shift || 'editors'; 
  
  my $sw = SangerWeb->new();
  
  my $cfg = Config::IniFiles->new( -file => $sw->server_root."/data/humpub/dbaccess" );
  
  die "Failed to parse dbaccess file" unless $cfg;
  
  my %users = map {$_ => 1} $cfg->val('users', $user_group);

  die "No users in group '$user_group'" unless %users;

  if ( $users{$sanger_user} ){
  	
  	if (wantarray) {
  		my $db_user = $cfg->val('db','user');
  		my $db_pass = $cfg->val('db','pass');
  	
  		die "DB username and/or password missing from dbaccess file" unless ($db_user && $db_pass);
  	
    	return ($db_user, $db_pass);
  	}
  	else {
  		return 1;
  	}
  }
  else {
    return wantarray ? (undef, undef) : undef;
  }
}

sub get_chromoDB_handle {

  # $user will be coming from single sign on
  # and has right to edit TPF
  my ($user, $password) = @_;

  my $dbname   = $CHROMODB_CONNECTION->{NAME};
  my $mach     = Net::Netrc->lookup($CHROMODB_CONNECTION->{HOST});

  if ( (defined $user and $user eq 'public') ){
    # chromoview external users	
	$user = 'chromo_tpfedit';
    $password = undef;
  }
  elsif ( $user and $password ){
    $password = $password;
  }	
  elsif ( $mach ){
    $password = $mach->password;
    $user     = $mach->login;
  }
  else {
    $user = $CHROMODB_CONNECTION->{RO_USER};
    $password = undef;
  }

  my $dbh = DBI->connect("DBI:mysql:host=$CHROMODB_CONNECTION->{HOST};port=$CHROMODB_CONNECTION->{PORT};database=$dbname",
                         $user, $password, { RaiseError => 1, PrintError => 0 })
    or die "Can't connect to chromoDB as '$user' ",
      DBI::errstr();

  return $dbh;
}

my $equiv_loutre_species = {
		'x.tropicalis' => 'tropicalis',
		'm.spretus'	   => 'mus_spretus',
		's.lycopersicum' => 'tomato'
};

sub get_loutre_dbname {
	my ($species) = @_;
	my $dbname = "loutre_";
	if($equiv_loutre_species->{$species}){
		$dbname .= $equiv_loutre_species->{$species};
	} else {
		$dbname .= $species;
	}

	return $dbname;
}

sub get_loutredbh_from_species {

  # $user will be coming from single sign on
  # and has right to edit TPF
  my ($species) = @_;

  my $host     = $LOUTRE_CONNECTION->{HOST};
  my $port     = $LOUTRE_CONNECTION->{PORT};
  my $user     = $LOUTRE_CONNECTION->{RO_USER};
  my $password = undef;

  if(!$species) {
  	return undef;
  }

  $species = lc($species);
  my $dbname = get_loutre_dbname($species);

  my $dbh;

  eval {
  	$dbh = DBI->connect("DBI:mysql:host=$host;port=$port;database=$dbname",
                         $user, $password, { RaiseError => 1, PrintError => 0 });
  };

  if(@$) {
  	return undef;
  }

  return $dbh;
}

sub get_script_root {
  return "/cgi-bin/humpub";
}

sub unixtime2YYYYMMDD {
  my $time = shift;
  my @t = localtime($time);
  my ($d, $m, $y) = @t[3..5];

  return join('-', ( $y+1900, sprintf("%02d", $m+1), sprintf("%02d",$d) ));
}
sub unixtime2datetime {
  my $time = shift;
  my @t = localtime($time);
  #  0    1    2     3     4    5     6     7     8
  # ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)

  my ($s, $min, $h, $d, $m, $y) = @t[0..5];

  return join('-', ( $y+1900, sprintf("%02d", $m+1), sprintf("%02d",$d) )) . ' ' .
              join(':', ( sprintf("%02d",$h), sprintf("%02d",$min), sprintf("%02d",$s)) );
}

sub unixtime2tpftime {
  my $time = shift;
  my @t = localtime($time);
  #  0    1    2     3     4    5     6     7     8
  # ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)

  my ($s, $min, $h, $d, $m, $y) = @t[0..5];

  my @months = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
  my $daypart;
  if($h > 12) {
  	$h -= 12;
  	$daypart = 'PM';
  }
  else {
  	$daypart = 'AM';
  }

  return sprintf("%s %2d %s %2d:%02d%s", $months[$m], $d, $y+1900, $h, $min, $daypart);

}

sub get_DNA_from_ftpghost {
  my ($acc ) = @_;
  my $qry = prepare_statement(qq{
                                 SELECT pa.project_name, s.file_path
                                 FROM project_acc pa, project_dump pd, sequence s
                                 WHERE pa.accession= ?
                                 AND pd.is_current=1
                                 AND pa.sanger_id=pd.sanger_id
                                 AND pd.seq_id=s.seq_id
                               });
  $qry->execute($acc);
  my ($projname, $filepath) = $qry->fetchrow;
  my $file = $filepath."/$projname";

  my $seqs ='';
  open(my $fh, $file) or die "$acc: $file not found\n";
  while (<$fh>){
    chomp;
    $seqs .= $_ if $_ !~ /^>/;
  }

  return uc($seqs);
}

sub get_latest_overlap_statusdate_of_TPF {

  # this will pick up clones found with overlaps after its belonging TPF has been created
  # from oracle database

  # if $longVersion: returns yyyy-mm-dd hh24:mm:ss; else: returns yyyy-mm-dd
  my ( $id_tpftarget, $longVersion ) = @_;

  my $qry = prepare_track_statement(qq{
                             SELECT TO_CHAR(MAX(os.statusdate), 'yyyy-mm-dd hh24:mm:ss')
                             FROM tpf_target tt, tpf t, tpf_row tr, clone_sequence cs,
                                  sequence_overlap so, overlap_status os
                             WHERE tt.id_tpftarget=t.id_tpftarget
                             AND t.id_tpf=tr.id_tpf
                             AND tr.clonename = cs.clonename
                             AND cs.is_current = 1
                             AND t.iscurrent =1
                             AND cs.id_sequence=so.id_sequence
                             AND so.id_overlap=os.id_overlap
                             AND os.iscurrent = 1
                             AND tt.id_tpftarget = ?
                           });
  $qry->execute($id_tpftarget);
  my $modtime = $qry->fetchrow;

  ($modtime) = $modtime =~ /(.*)\s.*/ unless $longVersion;

  return $modtime;
}

sub get_latest_clone_entrydate_of_TPF {

  # this will pick up clones modified after its belonging TPF has been created
  # from oracle database

  # if $longVersion: returns yyyy-mm-dd hh24:mm:ss; else: returns yyyy-mm-dd
  my ( $id_tpftarget, $longVersion ) = @_;
  my $qry = prepare_track_statement(qq{
                             SELECT TO_CHAR(MAX(cs.entrydate), 'yyyy-mm-dd hh24:mm:ss')
                             FROM tpf_target tt, tpf t, tpf_row tr, clone_sequence cs
                             WHERE tt.id_tpftarget=t.id_tpftarget
                             AND t.id_tpf=tr.id_tpf
                             AND tr.clonename = cs.clonename
                             AND cs.is_current = 1
                             AND t.iscurrent =1
                             AND tt.id_tpftarget = ?
                           });

  $qry->execute($id_tpftarget);
  my $modtime = $qry->fetchrow;

  ($modtime) = $modtime =~ /(.*)\s.*/ unless $longVersion;

  return $modtime;
}

sub get_TPF_modtime {

  # this will pick up clones modified after its belonging TPF has been created
  # from chromoDB.tpf_update (ie, depends on chron job being run already)

  my ( $id_tpftarget) = @_;
  my $dba = get_chromoDB_handle();
  my $sql =(qq{SELECT check_date
               FROM tpf_update
               WHERE id_tpftarget = $id_tpftarget
             });

#  $sql .= $subregion ? qq{AND subregion = '$subregion'} : qq{AND subregion is NULL};
#  $sql .= " ORDER BY check_date DESC LIMIT 1";

  my $qry = $dba->prepare($sql);
  $qry->execute;

  return $qry->fetchrow;
}

sub make_table_row {
  my ($trClass, $fields_hash, $dataArray) = @_;
  my $flds = '';
  foreach my $f ( @$dataArray ){
 #   warn $f, "---", $fields_hash->{$f};
    my $class = $fields_hash->{$f} || '';
    $f = '-' unless $f;
    $flds .= qq{<td class="$class">$f</td>};
  }

  return qq{<tr class="$trClass">$flds</tr>};
}

sub extra_footer_browsers {
  my ($id) = @_;
  my $msg = "Browser compatibility: Mozilla based browsers, eg, Firefox, Opera. For Internet Explorer, only IE-7 is supported";

  return qq{<div id='$id'>$msg</div>};
}

sub get_yyyymmdd {
  my $yymmdd = `date +%Y-%m-%d`;
  chomp $yymmdd;

  return $yymmdd;
}
sub get_mysql_datetime {

  # 0000-00-00 00:00:00
  my @t = split(/ /, scalar(localtime));
  return get_yyyymmdd()  . " " . $t[3];
}

sub datetime2unixTime {

  #expects time in yyyy-mm-dd hh:mm:ss format
  my( $time ) = shift;
  my( $year, $month, $day, $hour, $minute, $sec ) = split( /\W/, $time );
  my $oneday = 24 * 3600;       #for convenience
  my $utime = $sec + ($minute * 60) + ($hour * 3600); ## time in seconds on the day in question
  $year -= 1970;

  my @months = (31,28,31,30,31,30,31,31,30,31,30,31);

  for (my $i=0; $i < ($month-1); $i++ ) {
    $utime += ($months[$i] * $oneday);
  }

  $utime += ((($year - ($year%4))/4) * $oneday); ## take leap years into account
  if ( ($year%4)==0 && $month < 3 ) {
    $utime -= $oneday;
  }

  $utime += (($day-1) * $oneday);
  $utime += ($year * 365 * $oneday);

  return $utime;
}

sub make_hmenus {
  # horizontal menus
  my $species2chrTpf = Hum::Chromoview::ChromoSQL->fetch_species_chrsTpf();
  my $species2subregions_chrTpf = Hum::Chromoview::ChromoSQL->fetch_subregionsTpf();
  my $menu  = make_main_tabs('Chromosome', 'Subregion');
     $menu .= make_selection_menu($species2chrTpf, 'Chromosome');
     $menu .= make_selection_menu($species2subregions_chrTpf, 'Subregion');
     $menu .= initJscript();

  return $menu;
}

sub initJscript {
  return  qq{<script type="text/javascript">
             //initialize tab menu. Hiding subregion div by default
             mlddminit('subregion');
           </script>};
}

sub make_main_tabs {
  my (@tabs) = @_;

  my $scriptroot = get_script_root;

  my $menu = qq{<div id='tabs'>};
  $menu .= qq{<span id="chr_tab"><a id='chr_href' href='#' onMouseOver="show_hide_menu_by_tab('chromosome', 'subregion')">Chromosome</a></span>};
  $menu .= qq{<span id="sub_tab"><a id='sub_href' href='#' onMouseOver="show_hide_menu_by_tab('subregion', 'chromosome')">Subregion</a></span>};
  $menu .= qq{<span id="agp_tab"><a id='agp_href' target='_blank' href='$scriptroot/fetch_agp_errors'>AGP_errors</a></span>};
  $menu .= qq{</div>};

  return $menu;
}

sub make_selection_menu {

  my ($data, $set) = @_;

  my $scriptroot = get_script_root;
  my $url_a = "$scriptroot/fetch_contig_info";
  my $url_b = "$scriptroot/fetch_tpf_agp";

  my @jsparams = qw(agpButton contigBrowser tpf_table agp_table $loader $url_a $url_b);
  my $set_id = lc($set);

  my $menu = qq{<div id="$set_id">};
  $menu   .= qq{<ul class="mlddm" params="1,-1,0,none,0,h">};

  foreach my $species ( sort keys %$data ) {

    my $species_item = qq{<li><a href="#">$species</a><ul>};
    my $items = '';
    my $subitems = '';

    my (@AB, @H, @CHO, @NOD);   # for mouse, zfish, it's got very long list of subregions

    my @chrSubregions = sort { ace_sort($a, $b) } keys %{$data->{$species}};

    foreach my $chrSubregion ( @chrSubregions ) {

      my $id_tpftarget = $data->{$species}->{$chrSubregion};

      if ($chrSubregion !~ /_/ ) {
        my  $jslink = make_js_link($id_tpftarget, $species, $chrSubregion, 'fetchTpfTarget', $url_a, $url_b);
        $chrSubregion = 'Chromosome_'.$chrSubregion;
        $items .= qq{<li><a href="#" $jslink>$chrSubregion</a></li>};
      }
      else {
        my ($subregion, $chr_num) = split(/__/, $chrSubregion);
        $subregion = uri_escape($subregion);

        my ($chr) = $chr_num =~ /chr(.*)/; # or X, U...

        my $jslink = make_js_link($id_tpftarget, $species, $chr, 'fetchTpfTarget', $url_a, $url_b, $subregion);

        if ( $set eq 'Subregion' and $species eq 'Zebrafish' ) {
          if ( $chrSubregion =~ /^AB/ ) {
            push(@AB, [$chrSubregion, $id_tpftarget]);
          } elsif ( $chrSubregion =~ /^H/ ) {
            push(@H, [$chrSubregion, $id_tpftarget]);
          } else {
            $items .= qq{<li><a href="#" $jslink">$chrSubregion</a></li>};
          }
        } elsif ( $set eq 'Subregion' and $species eq 'Mouse' ) {
          if ( $chrSubregion =~ /^CHO/ ) {
            push(@CHO, [$chrSubregion, $id_tpftarget]);
          } elsif ( $chrSubregion =~ /^NOD/ ) {
            push(@NOD, [$chrSubregion, $id_tpftarget]);
          } else {
            $items .= qq{<li><a href="#" $jslink">$chrSubregion</a></li>};
          }
        } else {
          $items .= qq{<li><a href="#" $jslink">$chrSubregion</a></li>};
        }
      }
    }

    # deal with species with long list of subregions
    if ($set eq 'Subregion' and $species eq 'Zebrafish' ) {
      $subitems .= process_long_subregion_list($species, 'AB_regions', \@AB, $url_a, $url_b);
      $subitems .= process_long_subregion_list($species, 'H_regions', \@H, $url_a, $url_b);
    }
    elsif ($set eq 'Subregion' and $species eq 'Mouse' ) {
      $subitems .= process_long_subregion_list($species, 'CHO_regions', \@CHO, $url_a, $url_b);
      $subitems .= process_long_subregion_list($species, 'NOD_regions', \@NOD, $url_a, $url_b);
    }

    $menu .= $species_item . $subitems . $items . qq{</ul></li>};
  }

  $menu .= qq{</ul></div>};
  return $menu;
}

sub process_long_subregion_list {

  my ( $species, $region_name, $subregions, $url_a, $url_b ) = @_;

  my $items = '';
  $items .= qq{<li><a href='#' class='hsub'>$region_name</a><ul>};
  foreach (@$subregions) {
    my ($subregion, $chr_num) = split(/__/, $_->[0]);
    $subregion = uri_escape($subregion);

    my ($chr) = $chr_num =~ /chr(.*)/; # or X, U...
    my $jslink = make_js_link($_->[1], $species, $chr, 'fetchTpfTarget', $url_a, $url_b, $subregion);
    $items .= qq{<li><a href="#" $jslink>$_->[0]</a></li>};
  }
  $items .= qq{</ul></li>};

  return $items;
}

sub make_js_link {
  my ($id_tpftarget, $species, $chr, $function, $urla, $urlb, $subregion) = @_;
  $subregion = '' unless $subregion;
  return "onClick=\"$function". "('$id_tpftarget'," . "'$species',". "'$chr',". "'$urla'," . "'$urlb'," . "'$subregion');\"";
}

sub make_search_box {

  my $caption = qq{Search Project/Accession:&nbsp;};
  my $scriptroot = get_script_root;
  my $cgisrch = "$scriptroot/search_by_accession_or_clonename?seqname=";

  my $form = qq{<span><form class='search'>
              $caption
              <input class='searchbox' type='text'   value='' name='searchbox' />
              <input class='submit'    type='button' value='Search' onclick="accProjectSearch(this.form, 'searchbox', '$cgisrch');">
              <input class='reset'     type='reset'  value='Reset' />
             </form></span>
            };
  return $form;
}

sub phase_2_status {
  my ($phase) = @_;
  my $phase_2_status = {
                        1=>'unfinished',
                        2=>'contiguous',
                        3=>'finished'
                       };

  return $phase_2_status->{$phase};
}

sub concat_js_params {
  my @params = @_;
  return join(', ', map { "'".$_."'" } @params);
}

{
	# Store handles to avoid opening too many Oracle cursors
	my %latest_tpf_update_handle_for_sql;
	
	sub get_latest_TPF_update_of_clone {
	
	  my ($species, $chr, $subregion, $daySpan) = @_;
	  # get latest entrydate of current clone in a TPF
	
	  my @arguments;
	
	  my $sql = qq{
	               SELECT * from (
	               SELECT TO_CHAR(cs.entrydate, 'yyyy-mm-dd'), tg.id_tpftarget, cd.chromosome, tg.subregion, cd.speciesname, ROWNUM
	               FROM clone_sequence cs, clone c, tpf_row tr, tpf t, tpf_target tg, chromosomedict cd
	               WHERE cs.is_current=1
	               AND cs.clonename = c.clonename
	               AND c.clonename=tr.clonename
	               AND tr.id_tpf = t.id_tpf
	               AND t.ID_TPFTARGET=tg.ID_TPFTARGET
	               AND tg.chromosome=cd.id_dict
	               AND t.iscurrent=1
	               AND cd.speciesname = ?
	               AND cd.chromosome = ?
	             };
	             
	  push(@arguments, $species, $chr);
	             
	  my $csWindow;
	  if($daySpan) {
	  	$csWindow = qq{ AND cs.ENTRYDATE > sysdate-?};
	  	push(@arguments, $daySpan);
	  }
	  else {
	  	$csWindow = qq{ AND cs.ENTRYDATE < sysdate};
	  }

	  my $region;
	  if($subregion) {
	  	$region = qq{ AND tg.subregion = ?};
	  	push(@arguments, $subregion);
	  }
	  else {
	  	$region = qq{ AND tg.subregion IS NULL};
	  }
	
	  $sql .= $csWindow . $region;
	  $sql .= qq{ ORDER BY cs.entrydate DESC) WHERE ROWNUM <=1};
	  $sql .= qq{ UNION};
	  $sql .= qq{ SELECT DISTINCT TO_CHAR(t.entry_date, 'yyyy-mm-dd'), tg.id_tpftarget, cd.chromosome, tg.subregion, cd.speciesname, ROWNUM
	              FROM tpf t, tpf_target tg, chromosomedict cd
	              WHERE t.ID_TPFTARGET=tg.ID_TPFTARGET
	              AND tg.chromosome=cd.id_dict
	              AND t.iscurrent=1};
	  $sql .= qq{ AND cd.speciesname = ?
	              AND cd.chromosome = ?};
	              
	  push(@arguments, $species, $chr);
	             
	  my $tpfWindow = $daySpan ? qq{ AND t.entry_date > sysdate-$daySpan} : qq{ AND t.entry_date < sysdate};
	  $sql .= $tpfWindow . $region;
	  if($subregion) {
	  	push(@arguments, $subregion);
	  }
	
	  my $qry;
	  if(exists($latest_tpf_update_handle_for_sql{$sql})) {
	  		$qry = $latest_tpf_update_handle_for_sql{$sql}; 
	  }
	  else {
	  	$qry = prepare_track_statement($sql);
	  	$latest_tpf_update_handle_for_sql{$sql} = $qry;
	  }
	
	  $qry->execute(@arguments);
	
	  my $date_data = {};
	  my $date = '';
	  my $counter;
	  while ( my (@fields) = $qry->fetchrow() ){
	    $counter++;
	    pop @fields;
	    $date_data->{$fields[0]} = \@fields;
	  }
	  return unless $counter;
	
	  #warn "NUM: ", scalar keys %$date_data;
	  if (scalar keys %$date_data == 0 ){
	    return;
	  }
	  elsif (scalar keys %$date_data == 1 ){
	    return map { @{$date_data->{$_}} } keys %$date_data;
	  }
	  else {
	    my @Dt = sort { ace_sort($b, $a) } keys %$date_data;
	    return @{$date_data->{$Dt[0]}};
	  }
	}
}

sub get_all_current_TPFs {

  my $qry = prepare_track_statement(
    qq{
       SELECT cd.speciesname, cd.chromosome, tg.subregion
       FROM tpf t, tpf_target tg, chromosomedict cd
       WHERE t.id_tpftarget=tg.id_tpftarget
       AND tg.chromosome=cd.id_dict
       AND t.iscurrent=1
       ORDER BY cd.speciesname, cd.chromosome, tg.subregion
     });
  $qry->execute;

  my $os_chr_sub = [];
  while (my($species, $chr, $subregion) = $qry->fetchrow() ){
    push(@{$os_chr_sub}, [$species, $chr, $subregion]);
  }

  return $os_chr_sub;
}

sub get_species_chr_subregion_from_id_tpftarget {

  my ($id_tpftarget) = @_;
  my $qry = prepare_track_statement(qq{
                                       SELECT cd.speciesname, cd.chromosome, tt.subregion
                                       FROM tpf t, tpf_target tt, chromosomedict cd
                                       WHERE t.id_tpftarget=tt.id_tpftarget
                                       AND tt.chromosome=cd.id_dict
                                       AND t.id_tpftarget=?
                                       AND t.iscurrent=1
                                     });

  $qry->execute($id_tpftarget);
  my ($species, $chr, $subregion) = $qry->fetchrow();
  return ($species, $chr, $subregion);
}


1;

__END__

=head1 AUTHOR

James Gilbert email B<jgrg@sanger.ac.uk>

