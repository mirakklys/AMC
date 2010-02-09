#! /usr/bin/perl

use Getopt::Long;
use Graphics::Magick;
use AMC::Boite qw/min max/;
use XML::Simple;

my $scan='';
my $seuil=0.15;
my $analyse='';
my $output='';
my $zoom_plus=10;
my $largeur=800;

my $M_PI=atan2(1,1)*4;

GetOptions("scan=s"=>\$scan,
	   "seuil=s"=>\$seuil,
	   "analyse=s"=>\$analyse,
	   "output=s"=>\$output,
	   "largeur=s"=>\$largeur,
	   );

sub adapte {
    my ($im)=@_;
    return(sprintf("%.02f",100*$largeur/$im->Get('width')).'%');
}

my $an=XMLin($analyse,
	     ForceArray => [ 'analyse','chiffre','case','id','casetest' ],
	     KeyAttr=> [ 'id' ]);

my $cadre_general=AMC::Boite::new_complete_xml($an->{cadre});

my $page=Graphics::Magick::new();

$page->Read($scan);

my $bandeau;

if($an->{version}>=1) {
    $bandeau=$page->Clone();
    
    # mesure de l'angle de la ligne sup�rieure
    
    my $angle=$cadre_general->direction(0,1);
    my $dy_head=max($cadre_general->coordonnees(0,'y'),
		    $cadre_general->coordonnees(1,'y'));
    my $xa=$cadre_general->coordonnees(0,'x');
    my $xb=$cadre_general->coordonnees(1,'x');

    # coupe le haut de la page et le tourne pour qu'il soit droit

    $bandeau->Crop(int($xb-$xa)."x".int($dy_head)."+".$xa."+0");
    $bandeau->Rotate(-$angle*180/$M_PI);
    
    $bandeau->Annotate(text=>$an->{id},
		       geometry=>"+0+96",
		       font=>"Courier",pointsize=>96,
		       fill=>"blue",stroke=>"blue");

    $bandeau->Resize(geometry=>adapte($bandeau));
} else {
    $bandeau=Graphics::Magick::new();
}

my %morceaux=(0=>Graphics::Magick::new(),
	      1=>Graphics::Magick::new(),
	      );

@text_params=(font=>"Courier");

for my $k (sort { $an->{case}->{$a}->{r} <=> $an->{case}->{$b}->{r} } (keys %{$an->{case}})) {
    my $case=$an->{case}->{$k};

    my $coche=($case->{r}>$seuil ? 1 :0);
    my $boite=AMC::Boite::new_complete_xml($case);

    my $geometry=$boite->etendue_xy('geometry',$zoom_plus);

    # case
    $page->Draw(primitive=>'polygon',
		fill=>'none',stroke=>'blue',strokewidth=>1,
		points=>$boite->draw_points());
    
    if($an->{version}>=1) {
	# part de la case testee
	$page->Draw(primitive=>'polygon',
		    fill=>'none',stroke=>'magenta',strokewidth=>1,
		    points=>AMC::Boite::new_complete_xml($an->{casetest}->{$k})
		    ->draw_points());
    }

    my $e=$page->Clone();
    $e->Crop(geometry=>$geometry);

    # texte
    
    my $pt=24;

    ($x_ppem, $y_ppem, $ascender, $descender, $width, $height, $max_advance) =
	$e->QueryFontMetrics(text=>'9.999',@text_params,pointsize=>$pt);
    
    $pt=$pt*$e->Get('width')/$width*0.8;

    my $texte=Graphics::Magick::new();
    $texte->Set(size=>$e->Get('width').'x'.$e->Get('height'));
    $texte->ReadImage('xc:white');

    $color=($coche ? 'red' : 'blue');

    $texte->Annotate(text=>$k,
		     x=>2,y=>"-15%",
		     @text_params,pointsize=>$pt,gravity=>'West',
		     fill=>$color,stroke=>$color);
    $texte->Annotate(text=>sprintf("%.3f",sprintf("%.03f",$case->{r})),
		     x=>2,y=>"15%",
		     @text_params,pointsize=>$pt,gravity=>'West',
		     fill=>$color,stroke=>$color);

    push @$e,$texte;

    push @{$morceaux{$coche}},$e->Montage(geometry=>'+0+0');
}

%categories=(0=>'non coch�es',1=>'cases coch�es');

for(0..1) {
    my $titre=Graphics::Magick->new;
    $titre->Set(size=>$largeur.'x50');
    $titre->ReadImage('xc:white');
    $titre->Annotate("pointsize"=>40,
		     "gravity"=>'center',
		     "font"=>'Helvetica',
		     "fill"=>'blue',
		     "text"=>$categories{$_},
		     );
    push @$bandeau,$titre;

    my $i=$morceaux{$_}->Montage(tile=>'4x',geometry=>'+3+3',background=>'blue');
    $i->Resize(geometry=>adapte($i));
    push @$bandeau,$i;
}

$bandeau->Montage(tile=>'1x',geometry=>'+0+0',borderwidth=>3)->Write($output);

