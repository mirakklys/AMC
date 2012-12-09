#! /usr/bin/perl -w
#
# Copyright (C) 2012 Alexis Bienvenue <paamc@passoire.fr>
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

use AMC::Basic;
use AMC::Gui::Avancement;

use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempdir /;
use File::Copy;
use Unicode::Normalize;

use Getopt::Long;

use_gettext;

my $list_file='';
my $progress_id='';
my $copie='';
my $debug='';
my $vector_density=300;
my $orientation="";
my $rotate_direction="90";
my %use=(pdfimages=>1,pdftk=>1);

GetOptions("list=s"=>\$list_file,
	   "progression-id=s"=>\$progress_id,
	   "copy-to=s"=>\$copie,
	   "debug=s"=>\$debug,
	   "vector-density=s"=>\$vector_density,
	   "orientation=s"=>\$orientation,
	   "rotate-direction=s"=>\$rotate_direction,
	   "use-pdfimages!"=>\$use{pdfimages},
	   "use-pdftk!"=>\$use{pdftk},
	  );

set_debug($debug);

for my $cmd (qw/pdfimages pdftk/) {
  if($use{$cmd} && !commande_accessible($cmd)) {
    debug "WARNING: command $cmd not found";
    $use{$cmd}=0;
  }
}

$copie =~ s:(?<=.)/+$::;

sub original_file {
  my ($file_path)=@_;
  return({ path=>$file_path,orig=>1 });
}

sub derivative_file {
  my ($file_path)=@_;
  return({ path=>$file_path });
}

sub check_split_path {
  my ($f,$force)=@_;
  if($f->{path} && ($force || ! $f->{file})) {
    my ($fxa,$fxb,$file)=splitpath($f->{path});
    $f->{file}=$file;
    $f->{dir}=catpath($fxa,$fxb,'');
  }
}

my @f=map { original_file($_) } (@ARGV);

if(-f $list_file) {
  open(LIST,$list_file);
  while(<LIST>) {
    chomp;
    push @f,original_file($_);
  }
  close(LIST);
}

my $dp;
my $p;
$p=AMC::Gui::Avancement::new(1,'id'=>$progress_id)
  if($progress_id);

sub image_size {
  my ($file)=@_;
  my @r=();
  open(IDF,"-|",magick_module("identify"),"-format","%w,%h\n",$file);
  while(<IDF>) {
    chomp();
    @r=($1,$2) if(/([^,]+),(.*)/);
  }
  close(IDF);
  return(@r);
}

sub image_orientation {
  my ($file)=@_;
  my ($w,$h)=image_size($file);
  return( $h>1.1*$w ? "portrait" : $w>1.1*$h ? "landscape" : "");
}

sub move_derivative {
  my ($origin,$derivative)=@_;
  if(!$copie) {
    check_split_path($origin);
    check_split_path($derivative);
    my $dest=new_filename($origin->{dir}."/".$derivative->{file});
    debug "Moving $derivative->{path} to $dest";
    move($derivative->{path},$dest);
    $derivative->{path}=$dest;
    check_split_path($derivative,1);
  }
  return($derivative);
}

sub replace_by {
  my ($origin,@derivative_paths)=@_;
  my @fd=map { move_derivative($origin,derivative_file($_)) }
    @derivative_paths;
  unlink $origin->{path}
    if(!$origin->{orig});
  return(@fd);
}

# split multi-page PDF with pdfimages or pdftk, which uses less memory
# than ImageMagick

if($use{pdfimages} || $use{pdftk}) {

  my @pdfs=grep { $_->{path} =~ /\.pdf$/i } @f;
  @fs=grep { $_->{path} !~ /\.pdf$/i } @f;

  if(@pdfs) {
    $dp=1/(1+$#pdfs);
    $p->text(__("Splitting multi-page PDF files...")) if($p);

  PDF:for my $file (@pdfs) {

      $p->progres($dp) if($p);

      my $temp_loc=tmpdir();
      my $temp_dir = tempdir( DIR=>$temp_loc,
			      CLEANUP => (!get_debug()) );

      debug "PDF split tmp dir: $temp_dir";

      check_split_path($file);

      # First try pdfimages, which is much more judicious

      if($use{pdfimages}) {
	if(system("pdfimages","-p",$file->{path},
		  $temp_dir.'/'.$file->{file}.'-page')==0) {

	  opendir(my $dh, $temp_dir)
	    || debug "can't opendir $temp_dir: $!";
	  my @images=map { "$temp_dir/$_" }
	    sort { $a cmp $b } grep { /-page-/ } readdir($dh);
	  closedir $dh;

	  if(@images) {
	    # pdfimages produced some files. Check that the page
	    # numbers follow each other starting from 1

	    my $ok=1;
	  PDFIM: for my $i (0..$#images) {
	      if($images[$i] =~ /-page-([0-9]+)/) {
		my $pp=$1;
		if($pp != $i+1) {
		  debug "INFO: missing page ".($i+1)." from pdfimages";
		  $ok=0;
		  last PDFIM;
		}
	      }
	    }
	    if($ok) {
	      debug "pdfimages ok for $file->{file}";
	      push @fs,replace_by($file,@images);
	      next PDF;
	    }
	  } else {
	    debug "INFO: pdfimages produced no file";
	  }

	} else {
	  debug "ERROR while trying pdfimages: [$?] $!";
	}
      }

      # If not possible, use pdftk

      if($use{pdftk}) {
	if(system("pdftk",$file->{path},"burst","output",
		  $temp_dir.'/'.$file->{file}.'-page-%04d.pdf')==0) {

	  opendir(my $dh, $temp_dir)
	    || debug "can't opendir $temp_dir: $!";
	  my @burst=replace_by($file,
			       map { "$temp_dir/$_" }
			       sort { $a cmp $b } grep { /-page-/ } readdir($dh));
	  closedir $dh;

	  if(@burst) {
	    push @fs,@burst;
	    next PDF;
	  } else {
	    debug "WARNING: pdftk produced no file";
	  }

	} else {
	  debug "ERROR while trying pdftk burst: [$?] $!";
	}
      }

      # no success... keep it to be processed by magick

      push @fs,$file;

    }

    $p->text('') if($p);
  }

  @f=@fs;
}

# split other multi-page images (such as TIFF) with ImageMagick, and
# convert vector to bitmap

@fs=();
for my $fich (@f) {
  check_split_path($fich);

  my $suffix_change='';
  my @pre_options=();

  # number of pages :
  my $np=0;
  # any scene with number > 0 ? This may cause problems with OpenCV
  my $scene=0;
  open(NP,"-|",magick_module("identify"),"-format","%s\n",$fich->{path});
  while(<NP>) {
    chomp();
    if(/[^\s]/) {
      $np++;
      $scene=1 if($_ > 0);
    }
  }
  close(NP);
  # Is this a vector format file? If so, we have to convert it
  # to bitmap
  my $vector='';
  if($fich->{file} =~ /\.(pdf|eps|ps)$/i) {
    $vector=1;
    $suffix_change='.png';
    @pre_options=('-density',$vector_density)
      if($vector_density);
  }

  debug "> Scan $fich->{path}: $np page(s)".($scene ? " [has scene>0]" : "");
  if($np>1 || $scene || $vector) {
    # split multipage image into 1-page images, and/or convert
    # to bitmap format

    $p->text(sprintf(
		     ($vector
# TRANSLATORS: Here, %s will be replaced with the path of a file that will be converted.
		      ? __("Converting %s to bitmap...")
# TRANSLATORS: Here, %s will be replaced with the path of a file that will be splitted to several images (one per page).
		      : __("Splitting multi-page image %s...")),
		     $fich->{file})) if($p);

    my $temp_loc=tmpdir();
    my $temp_dir = tempdir( DIR=>$temp_loc,
			    CLEANUP => (!get_debug()) );

    debug "Image split tmp dir: $temp_dir";

    my $fb = $fich->{file};
    if(! ($fb =~ s/\.([^.]+)$/_%04d.$1/)) {
      $fb .= '_%04d';
    }
    $fb.=$suffix_change;

    system(magick_module("convert"),
	   @pre_options,$fich->{path},"+adjoin","$temp_dir/$fb");
    opendir(my $dh, $temp_dir) || debug "can't opendir $temp_dir: $!";
    push @fs,replace_by($fich,
			grep { -f "$_" } map { "$temp_dir/$_" }
			sort { $a cmp $b } readdir($dh));
    closedir $dh;

    $p->text('') if($p);
  } else {
    push @fs,$fich;
  }
}

@f=@fs;

# next, check files orientation and rotate them 90° if needed.

if($orientation) {

  my $temp_dir = tempdir( DIR=>tmpdir(),
			  CLEANUP => (!get_debug()) );

  @fs=();
  for my $fich (@f) {
    my $o=image_orientation($fich->{path});
    if($o && $o ne $orientation) {
      check_split_path($fich);

      debug "Rotate scan file $fich->{path} to orientation $orientation";
      my $dest=new_filename($temp_dir.'/rotated-'.$fich->{file});
      my @cmd=(magick_module("convert"),
	       $fich->{path},
	       "-rotate",$rotate_direction,
	       $dest);
      debug "CMD: ".join(' ',@cmd);

      if(system(@cmd)==0) {
	push @fs,replace_by($fich,$dest);
      } else {
	debug "Error while rotating $fich->{path}: $?";
	push @fs,$fich;
      }
    } else {
      push @fs,$fich;
    }
  }
  @f=@fs;

}

# if requested, copy files to project directory

if($copie && @f) {
  $p->text(__"Copying scans to project directory...") if($p);

  $dp=1/(1+$#f);

  my @fl=();
  my $c=0;
  for my $fich (@f) {
    check_split_path($fich);
    my $fb=$fich->{file};

    # no accentuated or special characters in filename, please!
    # this could break the process somewere...
    $fb=NFKD($fb);
    $fb =~ s/\pM//og;
    $fb =~ s/[^a-zA-Z0-9._+-]+/_/g;
    $fb =~ s/^[^a-zA-Z0-9]/scan_/;

    my $dest=$copie."/".$fb;
    my $deplace=0;

    if($fich->{path} ne $dest) {
      if(-e $dest) {
	# dest file already exists: change name
	debug "File $dest already exists";
	$dest=new_filename($dest);
	debug "--> $dest";
      }
      if(copy($fich->{path},$dest)) {
	push @fl,derivative_file($dest);
	$deplace=1;
      } else {
	debug "$fich->{path} --> $dest";
	debug "COPY ERROR: $!";
      }
    }
    $c+=$deplace;
    push @fl,derivative_file($fich->{path})
      if(!$deplace);

    $p->progres($dp) if($p);
  }
  debug "Copied scan files: ".$c."/".(1+$#f);
  @f=@fl;

  $p->text('') if($p);
}

open(LIST,">",$list_file);
for(@f) {
  print LIST $_->{path}."\n";
}
close(LIST);