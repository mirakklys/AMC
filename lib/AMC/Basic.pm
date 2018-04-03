# -*- perl -*-
#
# Copyright (C) 2008-2017 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 2 of
# the License, or (at your option) any later version.
#
# Auto-Multiple-Choice is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Auto-Multiple-Choice.  If not, see
# <http://www.gnu.org/licenses/>.

package AMC::Basic;

use Locale::gettext ':libintl_h';

use File::Temp;
use File::Spec;
use IO::File;
use Fcntl qw(:flock :seek);
use XML::Writer;
use XML::Simple;
use POSIX qw/strftime/;
use Encode;
use Module::Load;
use Module::Load::Conditional qw/check_install can_load/;
use Glib qw/TRUE FALSE/;

use constant {
    COMBO_ID => 1,
    COMBO_TEXT => 0,
};

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    @ISA         = qw(Exporter);
    @EXPORT      = qw( &perl_module_search &amc_specdir &get_sty &file2id &id2idf &get_ep &get_epo &get_epc &get_qr &file_triable &sort_from_columns &sort_string &sort_num &attention &model_id_to_iter &commande_accessible &magick_module &use_gm_command &magick_perl_module &debug &debug_raw &debug_and_stderr &debug_pm_version &set_debug &get_debug &debug_file &use_gettext &clear_old &new_filename &pack_args &unpack_args &__ &__p &translate_column_title &translate_id_name &pageids_string &studentids_string &studentids_string_filename &format_date &cb_model &get_active_id &COMBO_ID &COMBO_TEXT &check_fonts &amc_user_confdir &use_amc_plugins &find_latex_file &file_mimetype &file_content &amc_component &annotate_source_change &join_nonempty &string_to_usascii &string_to_filename &show_utf8 &path_to_filename &free_disk_mo);
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],

    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK   = qw();
}

# ---------------------------------------------------
# for path guess with local installation

my $amc_base_path;

if($ENV{'AMCBASEDIR'}) {
    $amc_base_path=$ENV{'AMCBASEDIR'};
} else {
    $amc_base_path=__FILE__;
    $amc_base_path =~ s|/Basic\.pm$||;
    $amc_base_path =~ s|/AMC$||;
    $amc_base_path =~ s|/perl$||;
}

sub amc_adapt_path {
    my %oo=@_;
    my @p=();
    my $r='';
    push @p,$oo{'path'} if($oo{'path'});
    push @p,map { "$amc_base_path/$_" } (@{$oo{'locals'}}) if($oo{'locals'});
    push @p,@{$oo{'alt'}} if($oo{'alt'});
    if($oo{'file'}) {
      TFILE: for(@p) { if( -f "$_/$oo{'file'}" )
		       { $r="$_/$oo{'file'}";last TFILE; } }
    } else {
      TDIR: for(@p) { if( -d ) { $r=$_;last TDIR; } }
    }
    return $r;
}

# ---------------------------------------------------

%install_dirs=(
    'lib'=>"/usr/lib/AMC",
    'libexec'=>"/usr/lib/AMC/exec",
    'libperl'=>"/usr/lib/AMC/perl",
    'icons'=>"/usr/share/auto-multiple-choice/icons",
    'models'=>"/usr/share/auto-multiple-choice/models",
    'doc/auto-multiple-choice'=>"/usr/share/doc/auto-multiple-choice-doc",
    'locale' => "/usr/share/locale",
    );

sub amc_specdir {
    my ($class)=@_;
    if($install_dirs{$class}) {
	return(amc_adapt_path(
		   'path'=>$install_dirs{$class},
		   'locals'=>[$class,'.'],
	       ));
    } else {
	die "Unknown class for amc_specdir: $class";
    }
}

sub perl_module_search {
  my ($prefix)=@_;
  $prefix =~ s/::/\//g;
  my %mods=();
  for my $r (@INC) {
    my $loc=$r.'/'.$prefix;
    if(-d $loc) {
      opendir(my $dh, $loc);
      for(grep { /\.pm$/i && -f "$loc/$_" } readdir($dh)) {
	s/\.pm$//i;
	$mods{$_}=1;
      }
      closedir $dh;
    }
  }
  return(sort { $a cmp $b } keys %mods);
}

# peut-on acceder a cette commande par exec ?
sub commande_accessible {
    my $c=shift;
    $c =~ s/(?<=[^\s])\s.*//;
    $c =~ s/^\s+//;
    if($c =~ /^\//) {
	return (-x $c);
    } else {
	$ok='';
	for (split(/:/,$ENV{'PATH'})) {
	    $ok=1 if(-x "$_/$c");
	}
	return($ok);
    }
}

my $gm_ok=commande_accessible('gm');

sub magick_module {
    my ($m)=@_;
    if($gm_ok) {
	return('gm',$m);
    } else {
	return($m);
    }
}

sub use_gm_command {
  return($gm_ok);
}

my $magick_pmodule='';

sub magick_perl_module {
    my ($dont_load_it)=@_;
    if(!$magick_pmodule) {
      TEST: for my $m (qw/Graphics::Magick Image::Magick/) {
	  if(check_install(module=>$m)) {
	      $magick_pmodule=$m;
	      last TEST;
	  }
      }
	if(!$magick_pmodule) {
	  debug(("*" x 85),
		"ERROR: none of the perl modules Graphics::Magick and Image::Magick are available!",
		"AMC won't work properly.",
		("*" x 85));
	}
	if($magick_pmodule && !$dont_load_it) {
	    load($magick_pmodule);
	    debug_pm_version($magick_pmodule);
	}
    }
    return($magick_pmodule);
}

# gets style file location

sub join_nonempty {
  my ($sep,@a)=@_;
  return(join($sep,grep { $_ } @a));
}

sub get_sty {
    my @r=();
    open(WH,"-|","kpsewhich","-all","automultiplechoice.sty")
	or die "Can't exec kpsewhich: $!";
    while(<WH>) {
	chomp;
	push @r,$_;
    }
    close WH;
    return(@r);
}

sub file2id {
    my $f=shift;
    if($f =~ /^[a-z]*-?([0-9]+)-([0-9]+)-([0-9]+)/) {
	return(sprintf("+%d/%d/%d+",$1,$2,$3));
    } else {
	return($f);
    }
}

sub id2idf {
    my ($id,%oo)=@_;
    $id =~ s/[\+\/]+/-/g;
    $id =~ s/^-+//;
    $id =~ s/-+$//;
    $id =~ s/([0-9]+-[0-9]+)-.*/$1/ if($oo{'simple'});
    return($id);
}

sub get_qr {
    my $k=shift;
    if($k =~ /([0-9]+)\.([0-9]+)/) {
	return($1,$2);
    } else {
	die "Unparsable Q/A key: $k";
    }
}

sub get_epo {
    my $id=shift;
    if($id =~ /^\+?([0-9]+)\/([0-9]+)\/([0-9]+)\+?$/) {
        return($1,$2);
    } else {
        return();
    }
}

sub get_epc {
    my $id=shift;
    if($id =~ /^\+?([0-9]+)\/([0-9]+)\/([0-9]+)\+?$/) {
        return($1,$2,$3);
    } else {
        return();
    }
}

sub get_ep {
    my $id=shift;
    my @r=get_epo($id);
    if(@r) {
        return(@r);
    } else {
        die "Unparsable ID: $id";
    }
}

sub file_triable {
    my $f=shift;
    if($f =~ /^[a-z]*-?([0-9]+)-([0-9]+)-([0-9]+)/) {
	return(sprintf("%50d-%30d-%40d",$1,$2,$3));
    } else {
	return($f);
    }
}

sub sort_num {
    my ($liststore, $itera, $iterb, $sortkey) = @_;
    my $a = $liststore->get ($itera, $sortkey);
    my $b = $liststore->get ($iterb, $sortkey);
    $a='' if(!defined($a));
    $b='' if(!defined($b));
    my $para=$a =~ s/^\((.*)\)$/$1/;
    my $parb=$b =~ s/^\((.*)\)$/$1/;
    $a=0 if($a !~ /^-?[0-9.]+$/);
    $b=0 if($b !~ /^-?[0-9.]+$/);
    return($parb <=> $para || $a <=> $b);
}

sub sort_string {
    my ($liststore, $itera, $iterb, $sortkey) = @_;
    my $a = $liststore->get ($itera, $sortkey);
    my $b = $liststore->get ($iterb, $sortkey);
    $a='' if(!defined($a));
    $b='' if(!defined($b));
    return($a cmp $b);
}

sub sort_from_columns {
  my ($liststore, $itera, $iterb, $sortkeys) = @_;
  my $r=0;
 SK:for my $c (@$sortkeys) {
    my $a = $liststore->get ($itera, $c->{'col'});
    my $b = $liststore->get ($iterb, $c->{'col'});
    if($c->{'type'} =~ /^n/) {
      $a=0 if(!defined($a));
      $b=0 if(!defined($b));
      $r=$a <=> $b;
    } else {
      $a='' if(!defined($a));
      $b='' if(!defined($b));
      $r=$a cmp $b;
    }
    last SK if($r!=0);
  }
  return($r);
}

sub attention {
    my @l=();
    my $lm=0;
    for my $u (@_) { push  @l,split(/\n/,$u); }
    for my $u (@l) { $lm=length($u) if(length($u)>$lm); }
    print "\n";
    print "*" x ($lm+4)."\n";
    for my $u (@l) {
	print "* ".$u.(" " x ($lm-length($u)))." *\n";
    }
    print "*" x ($lm+4)."\n";
    print "\n";
}

sub bon_id {

    #print join(" --- ",@_),"\n";

    my ($l,$path,$iter,$data)=@_;

    my ($result,%constraints)=@$data;

    my $ok=1;
    for my $col (keys %constraints) {
      if($col =~ /^re:(.*)$/) {
	my $k=$1;
	$ok=0 if($l->get($iter,$k) !~ /$constraints{$col}/);
      } else {
	$ok=0 if($l->get($iter,$col) ne $constraints{$col});
      }
    }

    if($ok) {
	$$result=$iter->copy;
	return(1);
    } else {
	return(0);
    }
}

sub model_id_to_iter {
    my ($cl,%constraints)=@_;
    my $result=undef;
    $cl->foreach(\&bon_id,[\$result,%constraints]);
    return($result);
}

# aide au debogage

my $amc_debug='';
my $amc_debug_fh='';
my $amc_debug_filename='';

sub debug_general_info {
  print $amc_debug_fh "This is AutoMultipleChoice, version 1.3.0+git2018-03-21 (r:4007644)\n";
  print $amc_debug_fh "Perl: $^X $^V\n";

  print $amc_debug_fh "\n".("=" x 40)."\n\n";
  if(commande_accessible('convert')) {
    open(VERS,"-|",'convert','-version');
    while(<VERS>) { chomp; print $amc_debug_fh "$_\n"; }
    close(VERS);
  } else {
    print $amc_debug_fh "ImageMagick: not found\n";
  }

  print $amc_debug_fh ("=" x 40)."\n\n";
  if(commande_accessible('gm')) {
    open(VERS,"-|",'gm','-version');
    while(<VERS>) { chomp; print $amc_debug_fh "$_\n"; }
    close(VERS);
  } else {
    print $amc_debug_fh "GraphicsMagick: not found\n";
  }
  print $amc_debug_fh ("=" x 40)."\n\n";

}

sub debug_file {
    return($amc_debug ? $amc_debug_filename : '');
  }

sub debug_raw {
  my @s=@_;
  return if(!$amc_debug);
  for my $l (@s) {
    $l=$l."\n" if($l !~ /\n$/);
    if($amc_debug_filename eq 'stderr' || $amc_debug_filename eq 'stdout') {
      print $amc_debug_fh $l;
    } else {
      flock($amc_debug_fh, LOCK_EX);
      $amc_debug_fh->sync;
      seek($amc_debug_fh, 0, SEEK_END);
      print $amc_debug_fh $l;
      flock($amc_debug_fh, LOCK_UN);
    }
  }
}

sub debug {
    my @s=@_;
    return if(!$amc_debug);
    for my $l (@s) {
	my @t = times();
	debug_raw(sprintf("[%7d,%7.02f] ",$$,$t[0]+$t[1]+$t[2]+$t[3]).$l);
    }
}

sub debug_and_stderr {
  my @s=@_;
  debug(@s);
  if(!($amc_debug && $amc_debug_filename eq 'stderr')) {
    for(@s) {
      print STDERR "$_\n";
    }
  }
}

sub debug_pm_version {
     my ($module)=@_;
     my $version;
     if (defined($version = $module->VERSION())) {
         debug "[VERSION] $module: $version";
     }
}

my @debug_memory=();

sub next_debug {
  push @debug_memory,@_;
}

local *AMC_STDERR_BACKUP;

sub set_debug {
  my ($debug)=@_;
  if($debug) {
    my $empty=0;
    *AMC_STDERR_BACKUP=*STDERR;
    if($debug =~ /^(1|yes)$/i) {
      # Continue with already used file
      $debug=$amc_debug_filename || 'new';
    }
    if($debug eq 'stderr') {
      $amc_debug_fh=*STDERR;
      $amc_debug_filename='stderr';
    } elsif($debug eq 'stdout') {
      $amc_debug_fh=*STDOUT;
      $amc_debug_filename='stdout';
    } else {
      # Use a file for debug log
      if($debug =~ /^(new)$/i) {
        # Create new file
        $empty=1;
        $amc_debug_fh = new File::Temp(TEMPLATE =>'AMC-DEBUG-XXXXXXXX',
                                       SUFFIX => '.log',
                                       UNLINK=>0,
                                       DIR=>File::Spec->tmpdir);
        $amc_debug_filename=$amc_debug_fh->filename;
      } else {
        # Use file given as argument
        $empty = (!-s $debug);
        $amc_debug_fh=new IO::File;
        $amc_debug_filename=$debug;
        $amc_debug_fh->open($debug,">>");
      }
      $amc_debug_fh->autoflush(1);
    }
    binmode $amc_debug_fh;
    *STDERR=$amc_debug_fh;
    $amc_debug=1;
    debug("[".$$."]>>");
    debug_general_info() if($empty);

    debug(@debug_memory);
    @debug_memory=();
  } else {
    # Leave debugging mode…
    *STDERR=*AMC_STDERR_BACKUP if($amc_debug);
    $amc_debug=0;
  }
}

sub get_debug {
    return($amc_debug);
}

# noms de fichiers absolus ou relatifs

sub clear_old {
    my ($type,@f)=@_;
    for my $file (@f) {
	if(-f $file) {
	    debug "Clearing old $type file: $file";
	    unlink($file);
	} elsif(-d $file) {
	    debug "Clearing old $type directory: $file";
	    opendir(my $dh, $file) || debug "ERROR: can't opendir $file: $!";
	    my @content = grep { -f $_ } map { "$file/$_" } readdir($dh);
	    closedir $dh;
	    debug "Removing ".(1+$#content)." files.";
	    unlink(@content);
	}
    }
}

sub new_filename_compose {
  my ($prefix,$suffix,$n)=@_;
  $suffix='' if(!$suffix);
  my $file;
  do {
    $n++;
    $file=$prefix."_".sprintf("%04d",$n).$suffix;
    utf8::downgrade($file);
  } while(-e $file);
  return($file);
}

sub new_filename {
  my ($file)=@_;
  utf8::downgrade($file);
  if(! -e $file) {
    return($file);
  } elsif($file =~ /^(.*?)_([0-9]+)(\.[a-z0-9]+)?$/i) {
    return(new_filename_compose($1,$3,$2));
  } elsif($file =~ /^(.*?)(\.[a-z0-9]+)?$/i) {
    return(new_filename_compose($1,$2,0));
  } else {
    return(new_filename_compose($file,'',0));
  }
}

sub pack_args {
    my @args=@_;
    $pack_fh = new File::Temp(TEMPLATE =>'AMC-PACK-XXXXXXXX',
			      SUFFIX => '.xml',
			      UNLINK=>1,
			      DIR=>File::Spec->tmpdir);
    binmode($pack_fh,':utf8');
    my $writer = new XML::Writer(OUTPUT=>$pack_fh,
				 ENCODING=>'UTF-8',
				 DATA_MODE=>1,
				 DATA_INDENT=>2);
    $writer->xmlDecl('UTF-8');
    $writer->startTag('arguments');
    for(@args) { $writer->dataElement('arg',$_); }
    $writer->endTag('arguments');
    my $fn=$pack_fh->filename;
    $pack_fh->close;
    return('--xmlargs',$fn);
}

sub unpack_args {
    my @args=@_;
    if($args[0] eq '--xmlargs') {
	shift(@args);
	my $file=shift(@args);
	my $xa=XMLin($file,'ForceArray'=>1,'SuppressEmpty'=>'')->{'arg'};
	unshift(@args,@$xa);
	next_debug("Unpacked args: ".join(' ',@args));
    }
    return(@args);
}

my $localisation;
my %titles=();
my %id_names=();

sub use_gettext {
    $localisation=Locale::gettext->domain("auto-multiple-choice");
    # For portable installs
    if(! -f ($localisation->dir()."/fr/LC_MESSAGES/auto-multiple-choice.mo")) {
	$localisation->dir(amc_adapt_path(
			       'locals'=>['locale'],
			       'alt'=>[amc_specdir('locale'), $localisation->dir()],
			   ));
    }

    init_translations();
}

sub init_translations {
    %titles=(
# TRANSLATORS: you can omit the [...] part, just here to explain context
	'nom'=>__p("Name [name column title in exported spreadsheet]"),
# TRANSLATORS: you can omit the [...] part, just here to explain context
	'note'=>__p("Mark [mark column title in exported spreadsheet]"),
# TRANSLATORS: you can omit the [...] part, just here to explain context
	'copie'=>__p("Exam [exam number column title in exported spreadsheet]"),
# TRANSLATORS: you can omit the [...] part, just here to explain context
	'total'=>__p("Score [total score column title in exported spreadsheet]"),
# TRANSLATORS: you can omit the [...] part, just here to explain context
	'max'=>__p("Max [maximum score column title in exported spreadsheet]"),
	);
    %id_names=(
# TRANSLATORS: you can omit the [...] part, just here to explain context
	'max'=>__p("max [maximum score row name in exported spreadsheet]"),
# TRANSLATORS: you can omit the [...] part, just here to explain context
	'moyenne'=>__p("mean [means of scores row name in exported spreadsheet]"),
	);
}

sub translate_column_title {
    my ($k)=@_;
    return($titles{$k} ? $titles{$k} : $k);
}

sub translate_id_name {
    my ($k)=@_;
    return($id_names{$k} ? $id_names{$k} : $k);
}

sub format_date {
  my ($time)=@_;
  return(strftime("%x %X",localtime($time)));
}

sub pageids_string {
  my ($student,$page,$copy,%oo)=@_;
  my $s=$student.'/'.$page
    .($copy ? ':'.$copy : '');
  $s =~ s/[^0-9]/-/g if($oo{'path'});
  return($s);
}

sub studentids_string {
  my ($student,$copy)=@_;
  $student='' if(!defined($student));
  return($student.($copy ? ':'.$copy : ''));
}

sub studentids_string_filename {
  my ($student,$copy)=@_;
  $student='' if(!defined($student));
  return($student.($copy ? '-'.$copy : ''));
}

sub annotate_source_change {
  my ($capture,$transaction)=@_;
  my $t=time();
  debug "Annotate source has changed! Time=$t";
  $capture->begin_transaction('asCh') if($transaction);
  $capture->variable('annotate_source_change',$t);
  $capture->end_transaction('asCh') if($transaction);
}

sub __($) { return($localisation->get(shift)); }
sub __p($) {
    my $str=$localisation->get(shift);
    $str =~ s/\s+\[.*\]\s*$//;
    return($str);
}

### modeles combobox

sub cb_model {
    my @texte=(@_);
    my $cs=Gtk3::ListStore->new ('Glib::String','Glib::String');
    my $k;
    my $t;
    while(($k,$t)=splice(@texte,0,2)) {
	$cs->set($cs->append,
		 COMBO_ID,$k,
		 COMBO_TEXT,$t);
    }
    return($cs);
}

sub get_active_id {
  my ($combo_widget)=@_;
  my ($ok,$iter)=$combo_widget->get_active_iter;
  if($ok) {
    return($combo_widget->get_model->get($iter,COMBO_ID));
  } else {
    return('');
  }
}

sub check_fonts {
  my ($spec)=@_;
  if($spec->{'type'} =~ /fontconfig/i && @{$spec->{'family'}}) {
    if(commande_accessible("fc-list")) {
      my $ok=0;
      for my $f (@{$spec->{'family'}}) {
	open FC,"-|","fc-list",$f,"family";
	while(<FC>) { chomp();$ok=1 if(/./); }
	close FC;
      }
      if(!$ok) {
	my $re='('.join("|",map { quotemeta($_) } (@{$spec->{'family'}})).')';
	open FC,"-|","fc-list",":","file";
      FCL: while(<FC>) {
	  if(/$re:\s*$/) {
	    $ok=1;
	    last FCL;
	  }
	}
	close FC;
      }
      return(0) if(!$ok);
    }
  }
  return(1);
}

sub amc_user_confdir {
  my $d=Glib::get_home_dir().'/.AMC.d';
  utf8::downgrade($d);
  return($d);
}

sub use_amc_plugins {
  my $plugins_dir=amc_user_confdir.'/plugins';
  if(opendir(my $dh,$plugins_dir)) {
    push @INC,grep { -d $_ }
      map { "$plugins_dir/$_/perl" } readdir($dh);
    closedir $dh;
  } else {
    debug "Can't open plugins dir $plugins_dir: $!";
  }
}

sub find_latex_file {
  my ($file)=@_;
  return() if(!commande_accessible("kpsewhich"));
  open KW,"-|","kpsewhich","-all","$file";
  chomp(my $p=<KW>);
  close(KW);
  return($p);
}

sub file_mimetype {
  my ($file)=@_;
  if(defined($file) && -f $file) {
    if(check_install(module=>"File::MimeInfo::Magic")) {
      load("File::MimeInfo::Magic");
      return("File::MimeInfo::Magic"->mimetype($file));
    } else {
      if($file =~ /\.pdf$/i) {
	return("application/pdf");
      } else {
	return('');
      }
    }
  } else {
    return('');
  }
}

sub file_content {
  my ($file)=@_;
  my $c;
  local $/;
  open(FILE,$file);
  $c=<FILE>;
  close(FILE);
  return($c);
}

sub string_to_usascii {
  my ($s)=@_;
  utf8::decode($s);
  if(check_install(module=>"Text::Unidecode")) {
    autoload("Text::Unidecode");
    $s=unidecode($s);
  } elsif(check_install(module=>"Unicode::Normalize")) {
    autoload("Unicode::Normalize");
    $s=NFKD($s);
    $s =~ s/\pM//g;
  }
  $s =~ s/[^\x{00}-\x{7f}]/_/g;
  return($s);
}

sub show_utf8 {
  my ($s)=@_;
  my $u=$s;
  utf8::upgrade($u);
  return($u . (utf8::is_utf8($s) ? " (utf8)" : ""));
}

sub string_to_filename {
  my ($s,$prefix)=@_;
  $prefix='f' if(!$prefix);
  $s=string_to_usascii($s);
  $s =~ s/[^a-zA-Z0-9.-]/_/g;
  $s =~ s/^[^a-zA-Z0-9]/$prefix_/;
  return($s);
}

sub path_to_filename {
  my ($volume,$directories,$file) =
    File::Spec->splitpath(@_);
  return($file);
}

sub amc_component {
  my ($name)=@_;
  $0="auto-multiple-choice $name";
}

my @call=caller();

amc_component($1) if($call[0] eq 'main' && $call[1] =~ /AMC-([a-z0-9]+)\.pl$/i);

sub free_disk_mo {
  my ($path)=@_;
  if(can_load(modules=>{"Filesys::Df"=>undef})) {
    my $d=Filesys::Df::df($path,1024**2);
    if(defined($d)) {
      return(int($d->{bavail}));
    }
  }
  return undef;
}

1;
