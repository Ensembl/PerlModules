package Hum::Chromoview::Utils;

### Author: ck1@sanger.ac.uk


use vars qw{ @ISA @EXPORT_OK };
use strict;
use warnings;
use DBI;
use Net::Netrc;
use Hum::Chromoview::ChromoSQL;
use Hum::Sort ('ace_sort');
use Hum::Submission 'prepare_statement';
use Hum::Tracking ('prepare_track_statement');

#use Hum::Tracking qw{prepare_track_statement};

use URI::Escape;

@ISA = ('Exporter');
@EXPORT_OK = qw(
                add_banner
                make_table_row
                extra_footer_browsers
                get_yyyymmdd
                get_mysql_datetime
                get_chromoDB_handle
                make_hmenus
                make_search_box
                get_script_root
                phase_2_status
                concat_js_params
                unixtime2YYYYMMDD
                get_TPF_modtime
                get_DNA_from_ftpghost
                get_lastest_TPF_update_of_clone
                get_all_current_TPFs
               );

sub unixtime2YYYYMMDD {
  my $time = shift;
  my @t = localtime($time);
  my ($d, $m, $y) = @t[3..5];

  return join('-', ( $y+1900, sprintf("%02d", $m+1), sprintf("%02d",$d) ));
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

sub get_TPF_modtime {

  # this will pick up clones modified after its belonging TPF has been created
  #my ( $species, $chr, $subregion) = @_;
  my ( $id_tpftarget) = @_;
  my $dba = get_chromoDB_handle();
  my $sql =(qq{SELECT LEFT(check_date, 10)
               FROM tpf_check
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
    my $class = $fields_hash->{$f};
    $f = '-' unless $f;
    $flds .= qq{<td class="$class">$f</td>};
  }

  return qq{<tr class="$trClass">$flds</tr>};
}
sub add_banner {
  my ($id) = @_;
  my $msg = "<span id='chromoview'>ChromoView</span> - Clone / Assembly info of genomes at the Sanger Institute";
  return qq{<div id='$id'>$msg</div>};
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

sub get_chromoDB_handle {

  # $user will be coming from single sing on
  # and has right to edit TPF
  my $editor = @_;

  my $host     = 'otterpipe2';
  my $dbname   = 'chromoDB';
  my $port     = 3303;
  my $mach     = Net::Netrc->lookup($host);
  my ($user, $password);

  if ( $mach ){
    $password = $mach->password;
    $user     = $mach->login;
  }
  else {
    $user     = 'ottro';
    $password = undef;
  }

  if ($editor ){
    $password = 'lutralutra';
    $user = 'ottadmin';
  }

  my $dbh = DBI->connect("DBI:mysql:host=$host;port=$port;database=$dbname",
                         $user, $password, { RaiseError => 1, PrintError => 0 })
    or die "Can't connect to submissions database as '$user' ",
      DBI::errstr();

  return $dbh;
}
sub get_script_root {
  return "/cgi-bin/humpub";
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

sub get_lastest_TPF_update_of_clone {

  my ($species, $chr, $subregion, $daySpan) = @_;
  # get latest entrydate of current clone in a TPF

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
               AND cd.speciesname = '$species'
               AND cd.chromosome = '$chr'
             };
  my $csWindow = $daySpan ? qq{ AND cs.ENTRYDATE > sysdate-$daySpan} : qq{ AND cs.ENTRYDATE < sysdate};
  my $region = $subregion ? qq{ AND tg.subregion = '$subregion'} : qq{ AND tg.subregion IS NULL};

  $sql .= $csWindow . $region;
  $sql .= qq{ ORDER BY cs.entrydate DESC) WHERE ROWNUM <=1};
  $sql .= qq{ UNION};
  $sql .= qq{ SELECT DISTINCT TO_CHAR(t.entry_date, 'yyyy-mm-dd'), tg.id_tpftarget, cd.chromosome, tg.subregion, cd.speciesname, ROWNUM
              FROM tpf t, tpf_target tg, chromosomedict cd
              WHERE t.ID_TPFTARGET=tg.ID_TPFTARGET
              AND tg.chromosome=cd.id_dict
              AND t.iscurrent=1};
  $sql .= qq{ AND cd.speciesname = '$species'
              AND cd.chromosome = '$chr'};
  my $tpfWindow = $daySpan ? qq{ AND t.entry_date > sysdate-$daySpan} : qq{ AND t.entry_date < sysdate};
  $sql .= $tpfWindow . $region;

  #print $sql;

  my $qry = prepare_track_statement($sql);
  $qry->execute();

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

1;

__END__
