#
# Copyright (C) 2009 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 3 of
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

package AMC::NamesFile;

BEGIN {
    use Exporter   ();
    our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

    # set the version for version checking
    $VERSION     = 0.1.1;

    @ISA         = qw(Exporter);
    @EXPORT      = qw( );
    %EXPORT_TAGS = ( );     # eg: TAG => [ qw!name1 name2! ],

    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK   = qw();
}

sub new {
    my ($f,%o)=@_;
    my $self={'fichier'=>$f,
	      'encodage'=>'utf-8',
	      'separateur'=>':',
	      'debug'=>'',

	      'heads'=>[],
	  };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
    }

    bless $self;

    $self->{'lines'}=$self->load();

    return($self);
}    

sub reduit {
    my $s=shift;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return($s);
}

sub load {
    my ($self)=@_;
    my @heads=();
    my %data=();

    $self->{'noms'}=[];

    if(open(LISTE,"<:encoding(".$self->{'encodage'}.")",$self->{'fichier'})) {
      NOM: while(<LISTE>) {
	  chomp;
	  s/\#.*//;
	  next NOM if(/^\s*$/);
	  if(!@heads) {
	      if(/$self->{'separateur'}/) {
		  @heads=map { reduit($_) } split(/$self->{'separateur'}/,$_);
		  print STDERR "ENTETES : ".join(", ",@heads)."\n" if($self->{'debug'});
		  next NOM;
	      } else {
		  @heads='nom';
	      }
	  }
	  s/^\s+//;
	  s/\s+$//;
	  my @l=();
	  if($#heads>0) {
	      @l=map { reduit($_) } split(/$self->{'separateur'}/,$_);
	  } else {
	      @l=(reduit($_));
	  }
	  if($#l!=$#heads) {
	      print STDERR "Mauvais nombre de champs (".(1+$#l)." au lieu de ".(1+$#heads).") fichier ".$self->{'fichier'}." ligne $.\n";
	  } else {
	      my $nom={};
	      for(0..$#l) {
		  $nom->{$heads[$_]}=$l[$_];
		  $data{$heads[$_]}->{$l[$_]}++;
	      }
	      push @{$self->{'noms'}},$nom;
	  }
      }
	close LISTE;
	$self->{'heads'}=\@heads;
	$self->{'keys'}=[grep { my @lk=(keys %{$data{$_}}); 
				$#lk==$#{$self->{'noms'}}; } @heads];
	return(1+$#{$self->{'noms'}});
    } else {
	return(0);
    }
}

sub heads { # entetes
    my ($self)=@_;
    return(@{$self->{'heads'}});
}

sub keys { # entetes qui peuvent servir de cle unique
    my ($self)=@_;
    return(@{$self->{'keys'}});
}

sub liste {
    my ($self,$head)=@_;
    return(map { $_->{$head} } @{$self->{'noms'}} );
}

sub data {
    my ($self,$head,$c)=@_;
    my @k=grep { $_->{$head} eq $c } @{$self->{'noms'}};
    if($#k==0) {
	return($k[0]);
    } else {
	print STDERR "Erreur : nom non unique (".(1+$#k)." exemplaires)\n";
	return();
    }
}

1;

__END__

perl -e 'use AMC::NamesFile;use Data::Dumper; $a=AMC::NamesFile::new("essais/liste.txt","debug"=>1);print $a->{"lines"}."\n";print "CLES : ".join(", ",$a->keys())."\n";print "PRENOMS : ".join(", ",$a->liste("prenom"))."\n";print Dumper($a->data("etu","10807389"));print Dumper($a->data("prenom","Mathieu"));'
