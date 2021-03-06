#!/usr/bin/perl -w

# USAGE:
# perl extractMD_OAI.pl oai set out format
#    oai: gallica, europeana
#    set OAI (e.g. gallica:corpus:1418 / gallica:corpus:1418Europeana  / gallica:corpus:BNUS1418Europeana
#    out : output folder
#    format : xml

# Example:
# >perl extractMD_OAI.pl europeana 9200579_Ag_UK_WellcomeCollection_IIIF OUT xml
# >perl extractMD_OAI.pl gallica gallica:corpus:1418 OUT xml

# OBJECTIVES:
# 1. Extract the illustrations metadata of documents described in a OAI-PMH repository (from a set or from a list of IDs)
# 2. Enrich the metadata : theme classification, color mode, captions


#####################
# use strict;
use warnings;
use 5.010;
use Data::Dumper;
use utf8::all;
use Net::OAI::Harvester; # for OAI-PMH # Installation : cpan -fi Net::OAI::Harvester
use LWP::Simple;
use Lingua::Stem::Any;
use Switch;
use Try::Tiny;
use Image::Info qw(image_info dim);
use Benchmark qw(:all) ;
use EDM qw( /Users/bnf/Documents/BnF/Dev/GallicaPix/OAI ); # path must be set for the Eureopana Data Model OAI package


######################
# global variables #
######################
%hash = ();	   	# hash table of metadata/value  pairs
$calculARK = 0; #  ark IDs must be exported? (used in bib-XML.pl)
my $couleur;  	# color mode
my $genre;    	# illustration's genre: photo, drawing, map... (similar to dc:type)
my $type;    	  # document type: monograph, newspaper...
my @sujets;			# illustration's subjects (dc:subject)
my $theme;    	# illustration's IPTC theme
my $personne; 	# the illustration is a person portrait?
my $pageExt;  	# page number to be extracted  -> see getRecordOAI_page()
my $harvester ;

#########################
### parameters to be set  ##
$reprise = 1 ; # to start the harvest at record X
$DPI_photo = 600; # default DPI value for photos
$DPI_imp = 400; # default DPI value for print content
$facteur_imp = 25.4/$DPI_imp; # converting pixels to mm
$facteur_photo = 25.4/$DPI_photo;
$A8 = 3848; # A8 surface (mm2)

### uncomment the following parameters to override a default value
my $genreDefaut = "partition";    #  illustrations default genre
my $typeDefaut = "I";  # default collection type  :  newspapers : P, magazine : R, monograph = M, image = I, manuscript = A, music scores = PA, maps: M
#my $IPTCDefaut = "0";   # default IPTC theme
my $couleurDefaut = "coul";  # default color mode: coul / gris / monochrome

### uncomment the following parameters to defined image classification tags applied to all illustrations
#my @tags = ("animal", "bird", "verterbrate"); # populate this list to create tags (English)
#my $sujets2tags = 1; # define this flag to use all dc:subjects as classification tags

# debugging mode
$DEBUG = 1;
$exportBnF = 1; # used by bib-XML.pl to export more metadata at the illustration level
########################




#findPerson("Jean Emile Raymond (1860-1934)");
#die

## import of XML output macros ##
require "../bib-XML.pl";

# APIs Gallica and Europeana
$urlAPIbnf = "https://gallica.bnf.fr/services/Pagination?ark="; # Gallica Pagination API
$urlAPIeuropeana = "https://www.europeana.eu/api/v2/record/"; # Europeana Record API
$urlGallica = "https://gallica.bnf.fr/ark:/12148/"; # Gallica URL prefix
$cleEuropeana = "cSQ72DjmT";

# OAI endpoints
$urlOAIbnf = "http://oai.bnf.fr/oai2/OAIHandler";  # Gallica OAINUM endpoint
$urlOAIeuropeana = "http://oai.europeana.eu/oaicat/OAIHandler";
# http://oai.bnf.fr/oai2/OAIHandler?verb=ListSets
# https://api.europeana.eu/oai/record?verb=ListSets
# OAI data models
$MDeuropeana = "edm";
$MDbnf = "oai_dc";

# patterns for XML extraction
# API Gallica: Pagination
$motifOrdre = "\<ordre\>(\\d+)\<\/ordre\>" ;
$motifLargeurBnF = "\<image_width\>(\\d+)\<\/image_width\>" ;
$motifHauteurBnF = "\<image_height\>(\\d+)\<\/image_height\>" ;
$motifNumero = "\<numero\>(.*)\<\/numero\>" ;
$motifToc = "\<hasToc\>(\\w+)\<\/hasToc\>" ;
$motifOcr = "\<hasContent\>(\\w+)\<\/hasContent\>" ;
$motifLeg = "\<legend\>(.*)\<\/legend\>" ;
#$motifLeg = "\<numero\>(.*)\<\/numero\>" ;
$motifFirst = "\<firstDisplayedPage\>(\\d+)\<\/firstDisplayedPage\>" ;
$motifPage = ".*/f(\\d+)" ;

# Europeana EDM
$motifLargeurEDM = "width\": (\\d+)" ;
$motifHauteurEDM = "height\": (\\d+)" ;
$motifCoulEDM = "edmHasColorSpace\":\"(.*?)\"" ; # non-greedy
$motifIIIFEDM = "dctermsIsReferencedBy\":(.*?)info.json" ; # non-greedy

# Misc.
my $dateMin;   # to filter documents on dates
my $dateMax;
my $nbPages = 1;

# Stats #
my $nbTotDocs=0;
my $nbMaxDocs=3;
my $nbTotIlls=0;
my $noClass = 0;$noGenre = 0;$noType = 0;
my $noRecord = 0; $nbDates = 0;
my $nbPerio = 0;$nbMono = 0;$nbManu = 0;
my $nbIIIF=0;

# IPTC words network for WW1 topic
my
# http://cv.iptc.org/newscodes/mediatopic/01000000
# themes
%iptc = (
	"guerr gard armé bataill militair pilot pillag canon épé boucli munit troph poilu poilus char chass invalid
  destroi  arme manoeuvr armii
  assaut monu offici camp   projectil   traducteur prisonni ennem sous-marin drapeau
    destruct biplan alert  fortification    mobilis casqu bombard médaill
   étendard dommag casemat   général bombardi capitain soldat casern croiseur navy
   fort képi raid torpilleur destroyer victoir drapeau masqu espionnag
   cadavr patrouilleur capitul commémor commémorativ canonni démolit cuirass antiaérien
   fleury douaumont verdun pruss autriche-hongr clemenceau
	 military army arms"  => "16",
   #Conflits, guerres et paix

	"patrimoin spectacl  artist architectur amphitheatr peintur retabl
	chanson acteur  statu cloîtr symphon muraill aren chant piano poem parol
	tow  estamp costum beffrois mélod  poésie musiqu music  chansonnette-march
	allégor théâtr boulevard partit  hymn vals tour clocher trianon monument
	château opéra escali salon exposit colon   beffroy violoncel orgu
	panthéon bastill versaill concord porte  danse cinem
	franc espagn allemagn portugal roussillon lectur orchest concert"
	=> "01",
	# Arts, culture et div., patrimoine

  "proces tribunal" => "02",
  #Criminalité, droit et justice

  "naufrag inond incend érupt catastroph explos effondr cru" => "03",
  #Désastres et accidents

  "agriculteur commerc vêt transport bovin agricol ponton pont légum horticultur port banqu
  agricultur industr ciment charbon   hall prêt canal post recyclag manufactur cargo presse
  coton moulin chanti econom vent collect  assur emprunt" => "04",
  #Economie et finances

  "enseignement écol lycée scout bibliothequ class scolair" => "05",
  #Education

  "" => "06",
  #Environnement

  "hôpital réadapt greff gripp sanatorium  secrétariats-greff hygien
  tuberculos tubercul blessur amput ambulance alcool santé pharmac
	hospital casualty wounded medical medicine respirator quinine laboratory nurse wound infirmary" => "07",
  #Sante

  "cheval serpent femm homm enfant person rein cardinal princess diplomat consul roi princ ministr
  ambassadeur empereur duc pape maharajah maréchal
  baigneux  famill épous joueur déput  président animali" => "08",
  "portr portrait" => "08p",
  #Gens animaux insolite

  "manifest défil foul voier usin quais entretien associ grev cheminot
  restaur bureau secrétariat sapeurs-pomp foul ferm
	factory" => "09",
  #Social, Monde du travail

  "bain pêch viand foir caf viand oeuf commerc neig trottinet fromager parfumer
  marché cerceau  motocyclet épicer boucher gare  vacanc fêt roserai  orchestr polic
  jeux hiv ballon cyclist autobus palac  carbur piscin fontain promenad plag baigneur
  divert rob chambr  bicyclet mair  vill conducteur noël poulaill mariag journal
  balcon habit villag tourist tourism  hôtel pompi tricot danseur mall parisien
  canotag traîneau maison boulevard cognac cigaret lamp boisson eau tabac éclairag
  horloger magasin cirqu aliment parfum mode biscuiter " => "10",
  #Vie quotidienne et loisirs

  "inaugur réunion candidat élect officiel mission  emprunt parlement
   parlementair révolu trait ministériel armistic histoir
   interparlementair conférence congrès polit républ fronti histoir" => "11",
   #Politique, histoire

  "églis eglis basiliq cathédral process abbay  ecclésiast
  musulman cimeti  prêch crucifix baptistère cloch  funérair chapel nef
  saint toussaint rit pèlerin crémati calvair mess tomb" => "12",
  #Religion et croyance

  "avion camion navir machin construct  automobil  invent paquebot  dirigeabl
  tracteur train véhicul bateau tramway gru brise-glac aqueduc
   " => "13",
  #Science et technologie

  "réfugi rapatri prison administr polic humanitair cris bienfais  aérien
  orphelinat nobless sécur garder civil anniversair maman press" =>  "14",
  #Société

  "sport sportiv sportif coureur nageur nageux natat plongeur basket-ball cavali cross
  cours side-car lanceur saut perch aviron boxeur équip marathon
  parachut football rugby patinag hippodrom hippiqu jockey compétit water-polo athlet marathon
  stad cricket gymnast cord équit tennis" => "15",
  #Sport

  "" => "17" #Météo
    	 );

###############################
# document types words network
	%types = (
			 	"monographie monographies"=> "M",
				"atlas carte cartes"=> "C",
				"périodique"=> "P",
			 	"manuscrit manuscript archive archives archival" => "A",
				"partition" => "PA",
				"image images" => "I"
			 	);

###############################
# document types words network
%personnes = (
				"enfant enfants" => "child",
				"madam  épous femm princess" => "woman",
				"homm offici général marin  prisonni aviateur pilot monsieur
				l'aviateur président soldat préfet directeur" => "man",
				"portrait portraits portr client sportif travailleur camarad personnel" => "person"
							 	);

###############################
# illustration genres words network
%genres = (
	"musique musical music hymne chanson partition symphonie" => "partition",
	"carte plan cartes plans" => "carte",
	"estampes estampe lithographiées litho. lithographe lithographiée eaux-fortes
	gravures gravure eau-forte engraving" => "gravure",
	"dessins dessin sketch sketchbook drawings drawing painting illustrateur dessinateur
	cartoons cartoon croquis satirique satiriques caricaturiste"
	=> "dessin",
	"photographie photograph photographique photogr photogr. phot.
	 aériennes aérienne stillimage image" => "photo",
	"manuscrit manuscript archive archives archival"
	=> "manuscrit"

	#"affiche"
	#=> "affiche"
	);

###############################

# lemmatization
$stemmer = Lingua::Stem::Any->new(language => 'fr',
         exceptions => {
            fr => {
            	basilique => 'basiliq',
            	dettes => 'dette',
            	dette => 'dette',
            	gare => 'gare',
                cargos  => 'cargo',
                rue  => 'rue',
                rues  => 'rue',
                baptistère => 'baptistère',
                baptistères => 'baptistère',
                ambulance  => 'ambulance',
                ambulances  => 'ambulance',
                conférences => 'conférence',
                conférence => 'conférence',
                dirigeable => 'dirigeabl',
                képi  => 'képi',
                képis  => 'képi',
                congrès => 'congrès',
                danse => 'danse',
                marché => 'marché',
                mode => 'mode',
                monument => 'monument',
                monuments => 'monument',
                pape => 'pape',
                parlement => 'parlement',
                portant => 'portant',
                porte  => 'porte',
                opéra => 'opéra',
                opéras => 'opéra',
                poésie => 'poésie',
                santé => 'santé',
                }
            });


####################################
# get one OAI record from its ID
sub getRecordOAI {my $id=shift;

	my $result = $harvester->getRecord(
		     metadataPrefix  => $MDprefix,
				 metadataHandler => $MDhandler,
		     identifier      => $id
    );

  if ( my $oops = $result->errorCode() ) {
		say "## OAI failed to get $id: ".$oops;
	  return}

  say "************** get record for $id ****************";
	my $header = $result->header();
	my $status = $header->status();
	say "--> status: $status";
	if ($status ne "deleted") {
		my $metadata = $result->metadata();
		my $type = getType($header,$metadata);
		my $storedId = getID($header);
		if ($storedId) {
  	  if (getMD($storedId,$metadata,$type)) {
         exportMD($storedId,$format)
      }
	  }
  }
}


####################################
# get only one page of a document
sub getRecordOAI_page {my $ark=shift;

	# arks have this form:  ark:/12148/btv1b8625630v/f12.image
	($pageExt ) = $ark =~ m/$motifPage/; # set the global var
	say "\npage : ".$pageExt;
	$ark = substr $ark, 0, (length($ark) - length($pageExt) - 8) ; # remove the end
	#say " ark : ".$ark;
	my $result = $harvester->getRecord(
		     metadataPrefix  => $MDprefix,
		     identifier      => $ark
    );

  if ( my $oops = $result->errorCode() ) { say "#### OAI error: ".$oops; die};
	my $header = $result->header();
	my $status = $header->status();
	say "--> status: $status";
	if ($status ne "deleted") {
		my $metadata = $result->metadata();
  	my $type = getType($header,$metadata);
  	my $tmp = getMD($id,$metadata,$type);
  	if (defined ($tmp)) {
       exportMD($ark,$format,$pageExt);   # we add the page number in the file name (in case several pages are asked for the same ID)
      }
    }
	}

####################################
# comput the OAI set size
sub getSizeOAI {my $set=shift;

	  my $r = 0;
    my $headers = $harvester->listAllIdentifiers(
        metadataPrefix  => $MDprefix,
				#metadataPrefix  => 'oai_dc',
        set => $set
    );

    if ( my $oops = $headers->errorCode() ) { say "#### OAI error: ".$oops; die};
    while ( my $header = $headers->next() ) {  # a Net::OAI::Record::Header object
        $r++;
    }
    say "_______________________\nRecords: $r\n_______________________";
    }


####################################
# get the whole OAI set
sub getOAI {my $set=shift;

my $header;
my $status;

## list the records set
my $records = $harvester->listAllRecords(
  metadataPrefix  => $MDprefix,
	metadataHandler => $MDhandler,
  set => $set
  #from => "1000"
    );
 say "...";

 # process the records
 while ( my $record = $records->next() ) {
 #while ( $nbTotDocs !=  $nbMaxDocs) {
	#print " . ";
	$nbTotDocs++;
	say "\n************************ #$nbTotDocs ************************";
	if ($nbTotDocs < $reprise) {next}

  if (defined($record)) {
    $header = $record->header();
		$status = $header->status();
		say "--> status: $status";
		if ($status eq "deleted") {
			next}
		}
	else {
    	say "#### OAI error while extracted record $id! ####".$record->errorCode();
			return undef
    	}

	my $storedId = getID($header);
	if ($storedId) {
			if (existsID($storedId)) {  # already done?
			  say "... already done in $OUT!";
				next
			}
		  my $metadata = $record->metadata();
		  my $type = getType($header,$metadata);

			#say Dumper ($header);
			#say "********";
			#say Dumper ($metadata);
    	#my $status = $header->status();
    	if (not (defined ($metadata))) {
        # (($header->headerStatus() eq "deleted") or ($header->status() eq "deleted"))) {
    		say "####  OAI: problem on record metadata $storedId!  ####";
    	}
      else {
				#say "before ";
				#say $hash{"id"};
     		my $ok = getMD($storedId,$metadata,$type);
				#say "after ";
				#say $hash{"id"};
     		if ($ok) {
      	  #my $fichier = $OUT."/".$id.".".$format;
       	  exportMD($storedId,$format);
       	  #if (($nbTotDocs % 10)==0) {say " ----- #$nbTotDocs -----";}
     		} else
      		{say "####  No record!  ####";
       		 $noRecord++}
       }
		  }
   }
}

# say if a record file already exists localy
sub existsID {my $id=shift;

  $tmp = $id;
  $tmp =~ s/\//-/g; # replace the / with - to avoid issues on filename
	my $ficOut = $OUT."/$tmp.".$format;
	if (-e $ficOut) {
		return 1
	}
}


##################################################
####                MAIN                      ####
##################################################
if (scalar(@ARGV)<4) {
	die "\nUsage : perl extractMD.pl oai set out format
oai: OAI repository name (gallica, europeana)
set : OAI set title
out : output folder
format : output format (xml)
	\n";
}

$oai=shift @ARGV;
# classification type
switch ($oai) {
 case "gallica" {$urlOAI=$urlOAIbnf;
						 $MDprefix = $MDbnf;
					   $MDhandler = ""}
 case "europeana" {$urlOAI=$urlOAIeuropeana;
									$MDprefix = $MDeuropeana;
								  $MDhandler = "EDM"}

 else {die " #### OAI name must be: gallica, europeana ####\n";}
}

$set=shift @ARGV;

# output folder
$OUT=shift @ARGV;
if(-d $OUT){
		say "Writing in $OUT...";
	}
	else{
		mkdir ($OUT) || die ("####  Error while creating folder: $OUT\n");
    say "Creating $OUT...";
	}

$format = shift @ARGV;

#######  create harvester instance
$harvester = Net::OAI::Harvester->new(
            baseURL => $urlOAI
           # baseURL => 'http://catoai.bnf.fr/oai2/OAIHandler'   # OAICAT
);

my $identity = $harvester->identify();
my $OAIname = $identity->repositoryName();
if ((defined $OAIname ) and (length $OAIname>0))
  {say "Harvesting OAI '".$identity->repositoryName(),"'...\n";}
else {
	say "#### OAI $urlOAI is not responding! ####";
	die}


#####################################
$t0 = Benchmark->new;

############################
## to get the OAI set size #
#getSizeOAI($set,$harvester);


################################
### to get the whole OAI set ###
#getOAI($set,$harvester);

# BnF : gallica:corpus:1418
# BnF : gallica:typedoc:images
#http://oai.bnf.fr/oai2//OAIHandler?verb=ListRecords&set=gallica:corpus:1418&metadataPrefix=oai_dc

# Europeana :
# 2020601_Ag_ErsterWeltkrieg_EU (WW1 Eastern Front)
# 9200579_Ag_UK_WellcomeCollection_IIIF : 92 000
#
# https://www.europeana.eu/portal/en/collections/world-war-I?f%5BPROVIDER%5D%5B%5D=Europeana+1914-1918&q=eastern+front&view=grid+
# 31746 results
# 2021719_Ag_CY_Theodosis_Nikolaou : 1 record
# 9200579_Ag_UK_WellcomeCollection_IIIF : 92,483 records


#######################
# to get one document #
#### BnF ####
#getRecordOAI("ark:/12148/bpt6k6234143v"); # image
#getRecordOAI("ark:/12148/btv1b530176112"); # image
getRecordOAI("ark:/12148/btv1b55002566f"); # partition


#die
#getRecordOAI("ark:/12148/btv1b53148749t");
#die
#getRecordOAI("ark:/12148/btv1b55002885z"); # monographie

#http://oai.bnf.fr/oai2//OAIHandler?verb=GetRecord&identifier=oai:bnf.fr:gallica/ark:/12148/btv1b6907528t&metadataPrefix=oai_dc

#### Europeana ####
# avec iiif :
#getRecordOAI("http://data.europeana.eu/item/9200211/en_list_one_vad_0342");
#http://www.europeana.eu/portal/en/record/9200211/en_list_one_vad_0342.html

# http://oai.europeana.eu/oaicat/OAIHandler?verb=GetRecord&identifier=http%3A%2F%2Fdata.europeana.eu%2Fitem%2F9200579%2Fz7unny8z&metadataPrefix=edm
#getRecordOAI("http://data.europeana.eu/item/9200579/zxah9kh2");
#getRecordOAI("http://data.europeana.eu/item/9200579/zssertsz");
#getRecordOAI("http://data.europeana.eu/item/9200579/b45fg9s4");
#getRecordOAI("http://data.europeana.eu/item/9200579/ajbfufpt");
#http://oai.europeana.eu/oaicat/OAIHandler?verb=GetRecord&identifier=http%3A%2F%2Fdata.europeana.eu%2Fitem%2F9200579%2Fajbfufpt&metadataPrefix=edm

# Sets :
# http://oai.europeana.eu/oaicat/OAIHandler?verb=ListSets

##################
# to get one page
#getRecordOAI_page("ark:/12148/btv1b7100627v/f761.image");

##################
# to load a list of arks stored in a external .pl file
#require "SRU-guerre-1418.pl";

$t1 = Benchmark->new;
$td = timediff($t1, $t0);
say "the code took:",timestr($td);

#####################################


say "\n=============================";
say "$nbTotDocs documents ";
say "$noRecord documents rejected ";
say "  $nbPerio periodical records ";
say "  $nbMono monographs";
say "  $nbManu manuscripts";
say "  $nbDates dates";
say "$noClass no theme ";
say "$noType no document type ";
say "$noGenre no illustration genre ";
say "--------------------";
say "illustrations: $nbTotIlls";
say "--------------------\n";
say "iiif: $nbIIIF";
##################################################
####            end MAIN                      ####
##################################################

######################################
# extract the ID
sub getID {my $header=shift;

    	my $id;

			my $tmp = $header->identifier();
			say "... record ID: $tmp";

    	if (defined ($tmp)) {
    	    $id = extractID($tmp);
				  say "ID: $id"} # extract the internal ID
    	else
    	  {say "#### ID unknown in the OAI! ####";
				 $noRecord++;
    	   say Dumper ($header)  ;
    	   return undef}

    	# to filter the periodical records
    	if (  $id =~ /date/ ) {
    		say "** ID $id is a periodical record --> filtering";
    		$nbPerio++;
				say Dumper ($header) ;
    		return undef}

			say "... stored ID: $id"; # store the ID
			$hash{"id"} = $id;
			#say $hash{"id"} ;
			return $id;
}

# extract the document collection (monographies, periodicals, images)
sub getType {my $header=shift;
						 my $metadata=shift;

			my @mots;

			switch($oai) {
	 			case "gallica" {
						my @tmp = $header->sets();
					  say "\n... type from OAI: @tmp";
						my $tmpMots = join(":",@tmp);
	 			    @mots = split(':',lc($tmpMots));}
				case "europeana" {
						my $tmp = $metadata->type();
					  say "\n... type from OAI: $tmp";
					  @mots = split(':',lc($tmp));}
      }

    	if (@mots) { # array of 'gallica:typedoc:cartes', ...
				 # confronting the metadata to the words network for illustration genres

				 foreach my $t  (@mots) {
				 	if ($DEBUG) {print $t." - ";}
				 	($match) = grep {$_ =~ /\b$t\b/} keys %types;
				 	 if ($match) {
				 			my $type = $types{$match};
				 			if ($type eq "P") {
				 				 say "** NOK: periodical titles are not handled **";
				 				 $nbPerio++;
				 				 return undef;
				 				}
							elsif ($type eq "M") {
								$nbMono++;
								return $type}
							elsif ($type eq "A") {
									$nbManu++;
									return $type}
							else {
								say "... type: $type";
								return $type}
						}}
					$noType++;
					return "unknown"}
    	else
    	  {say "#### type unknown in the OAI! ####";
				say Dumper ($header)  ;
				$noType++;
				return "unknown"
			}
		}

# extract the internal ID from the OAI ID
sub extractID {my $id=shift;
	switch($oai) {
		 case "gallica" {return substr $id,30} # suppress ark:/12148/oai:bnf.fr:gallica/ to get the internal ID
		 case "europeana" {return substr $id,30} # suppress http://data.europeana.eu/item/ to get the internal ID
	 }
 }

######################################
# extract the metadata
sub getMD {my $id=shift;
					 my $metadata=shift;
					 my $typeOAI=shift;

    	my $ark;
    	my $match;
			my $dcsujets="";
			my $dcauteurs="";
			my $dctypes="";
			my $dcformats="";
			my $dclang="";
			my $dcdescriptions="";
			my @props;

    	# Reset the hash
    	%hash = ();
    	undef $couleur;
    	undef $personne;

			if ($oai ne "gallica") { # do we have a IIIF resource?
			 my $isReferencedBy = $metadata->isReferencedBy();
			 if (not defined $isReferencedBy) {
				say "### unknown isReferencedBy ###";
			 }
			 elsif (index($isReferencedBy,"iiif") == -1) {
				say "### not IIIF compliant ###";
				return undef}
			else {
				say "** IIIF compliant : $isReferencedBy"}
			}

			# dc:subjet
			@sujets = $metadata->subject();  # sometimes we have multiple subject fields
			#say Dumper @sujets;
			if ($sujets[0]) {
				$dcsujets = join (' -- ',@sujets)  ;
				$hash{"sujet"} = escapeXML_OAI($dcsujets);
				say " subject: $dcsujets"}

			# dc:description
			my @descriptions = $metadata->description();  # sometimes we have multiple subjet fields
			if ($descriptions[0]) {
					$dcdescriptions = join (' -- ',@descriptions)  ;
					$hash{"description"} = escapeXML_OAI($dcdescriptions);
					say " description: $dcdescriptions"}

			# hack for Europeana
			if ($oai ne "gallica") { # do we have a WW1 resource?
			 if (index(lc($dcsujets),'war one') == -1) {
					say "### not a WW1 document ###";
					return undef}
      }

    	if (defined ($dctitre = $metadata->title())) {
    		$hash{"titre"} = escapeXML_OAI($dctitre);
    		say " title: $dctitre";
    	}
    	  # $hash{"1_ill_1_leg"} = escapeXML($titre);} # on copie le titre dans le champ légende (il s'agit d'images)
    	  # a revoir si docs multipages
    	else
    	   {if ($DEBUG) {say "** Unknown title for ID $id! **";}
    	}

			my @coverages = $metadata->coverage();  # sometimes we have multiple subjet fields
			if ($coverages[0]) {
					$dccoverages = join (' -- ',@coverages)  ;
					$hash{"couverture"} = escapeXML_OAI($dccoverages);
					say " coverage: $dccoverages"}

			# language
			if (defined ($dclang = $metadata->language())) { # try on dc:lang
			  say " dc:language: $dclang";
    	}
			if ($oai eq "europeana") {
				if (defined ($dclang = $metadata->edmLanguage())) { # try on edm:language
			  say " dc:edmLanguage: $dclang";}
			}
			if ((defined $dclang) and ($dclang ne "0")) {
				$hash{"lang"} = $dclang;
			}
			else {
				$hash{"lang"} = "fre"; # default
			  say " language: fre (default)";
			}

			if (defined ($dcsource = $metadata->source())) {
    		$hash{"source"} = $dcsource;
    		say " source: $dcsource";
    	}

			if (defined ($ressource = $metadata->resource()) and ($ressource ne "0")) {
    		$hash{"url"} = $ressource;
    		say " ressource: $ressource";
    	}
    	# dates
    	my $tmp = $metadata->date();
    	# filter on dates
    	if ((defined $dateMin) && (defined $tmp) && ($tmp < $dateMin)) {
    		if ($DEBUG) {say "** filter on date min: $dateMin";}
    		$nbDates++;
    	  return undef}
    	if ((defined $dateMax) && (defined $tmp) && ($tmp > $dateMax)) {
    		if ($DEBUG) {say "** filter on date max: $dateMax";
    			}
    		$nbDates++;
    	  return undef}
    	$tmp ||= "inconnu";
    	$hash{"date"} = $tmp;
    	say " date: $tmp";

    	# source of document types : newspapers, image, monographs...
    	if (defined $typeDefaut) {   # if we have a default type
    	    $tmp = $typeDefaut}
			elsif ($typeOAI and ($typeOAI ne "unknown")) {
				$tmp = $typeOAI}
			else {
				say "### unkwown document type: can't proceed! ###";
				return undef}
			$hash{"type"} = $tmp;
			$type=$tmp;
			say " type: $tmp";

    	# dc:author
    	my @auteurs = $metadata->creator();
			if ($auteurs[0]) {
    		$dcauteurs = join (' -- ',@auteurs) ;
				$hash{"auteur"} = escapeXML_OAI($dcauteurs);
				say " creator: $dcauteurs" }
				else {
					$hash{"auteur"} = "inconnu"}

			# searching for illustrations genre  : photo/gravure/dessin/partition/carte/manuscrit
			if (defined $genreDefaut) {   # if we have a default value
    	    $genre = $genreDefaut}
			else {
				say "...looking for genre";
    	 my @dctypes = $metadata->type();
			 if ($dctypes[0]){
    	  $dctypes = join (' -- ',reverse @dctypes) ; # reverse because discriminative words are located at the end
				$hash{"types"} = escapeXML_OAI($dctypes);
				say " types: $dctypes"
				}
    	 # dc:format
    	 my @formats = $metadata->format();
			 if ($formats[0]) {
    		$dcformats = join (' -- ',@formats);
				$hash{"format"} = escapeXML_OAI($dcformats);
			  say " format: $dcformats" }
    	 # we add title because it can contains discriminative words
    	 @mots = split(' ',lc(escapePunct($dcformats." ".$dctitre." ".$dcsujets." ".$dcauteurs." ".$dctypes)));
			 if ($DEBUG){
				say "... looking in:";}
    	 # confronting the metadata to the words network for illustration genres
    	 foreach my $t  (@mots) {
				 #print $t." - ";
				if ((length($t) < 4) or ($t =~ /^[0-9,.E*°]+$/ ) )
				   {next} # don't process stop words and numbers
				$t =~ tr/*{}/ /;
    		if ($DEBUG) {print $t." - ";}
    		($match) = grep {$_ =~ /\b$t\b/} keys %genres;
    	   if ($match) {
    	      $genre = $genres{$match};
    	      last;}
    	 }
    	 if (not (defined $match)) {
    		say "\n** unknown illustration genre: @mots **";
    	  $genre = "inconnu";
    		$noGenre++;}
			}
    	say "\n illustration genre: $genre";
			$hash{"genre"} = $genre;

			# color mode
      if (defined $couleurDefaut) {   # if we have a default type
			   $couleur = $couleurDefaut}
			else {
				say "...looking for color mode";
    	 # loooking for document color mode on dc:format
    	 if ($genre eq "photo") {
    	    $couleur = "gris" ;}  # assumption
    	 if ( $dcformats  =~  m/.+coul\..+/) {
    	   $couleur = "coul"}
			 }
			$couleur ||= "inconnu";
    	say " color mode: $couleur";

			# person classification
			# looking for people in title and subject
			say "...looking for people in title and subjects";
			@mots = split(' ',lc(escapePunct($dctitre." ".$dcsujets)));
			my @motsLem  = $stemmer->stem(@mots);
			# confronting the metadata to the words network for people
			foreach my $t  (@motsLem) {
				if ((length($t) < 4) or ($t =~ /^[0-9,.E*°]+$/ ) )
					{next} # don't process stop words and numbers
				$t =~ tr/*{}/ /;
				{print $t." - ";}
				($match) = grep {$_ =~ /\b$t\b/} keys %personnes;
				if ($match) {
					 if ($DEBUG) {say ""}
					 $personne = $personnes{$match};
					 if ($DEBUG) {say " -> $personne"}
					 last;}
				 }
				if ($DEBUG) {say  "\n"}


			if (not (defined $personne))  { # using regexp to find a person name in the title
				if ($DEBUG) {say " ... looking for named entities in subjects"; }
				#$tmp = join(' ',$dctitre." ".$dcsujets); #
				foreach my $ch (@sujets) {
					say $ch;
					if (findPerson($ch)) {
						if ($DEBUG) {say " -> person in title/subject";}
						$personne = "person";
						last;
							}
						}
					}

			# IPTC theme
      if (defined $IPTCDefaut) { # if we have a default type
				 $theme = $IPTCDefaut
			} else {
    	 say "...looking for theme";
    	 if (@sujets) {
    		# searching for theme in the IPTC words network
    		 $theme = extractIPTC($dcsujets);
    		 if (not (defined ($theme))) {
    			 if ($DEBUG) {say " FAIL on dc:subject"};
    		   $theme = extractIPTC($dctitre);} # next try on dc:title
    	  }
    	  else  # if no dc:subject, let's try on title
    	  {
					if ($DEBUG) {say " FAIL on dc:subject"};
					$theme = extractIPTC($dctitre);}
  	    # last try
    	  if (not (defined ($theme)) and (defined $dcdescriptions)) { # try on dc:description
         if ($DEBUG) {say " ... try on dc:description"}
				 $theme = extractIPTC($dcdescriptions);
			  }
        # last try on document types
			  if (not (defined $theme)) {
         if ($genre eq "partition")
             {$theme="01";}  # "arts"
         elsif ($genre eq "carte")
             {$theme="13";} # "sciences"
        }
      }

			# conclusions
			if ((not (defined $personne)) and (defined $theme) and ($theme eq "08p")) {
				 $personne = "person"}
			if ((not (defined $theme)) and (defined $personne)) {
				$theme = "08p"}
 			$theme ||= "inconnu";
      if (not (defined ($theme))) {
				$noClass++}
      say " IPTC theme: $theme";
			if (defined $personne) {
				say " person: $personne"}

    	# extract dimensions
			say "... looking for pagination and dimension information";
			switch ($oai) {
			 case "gallica" {@props = extractGallicaProperties($id);}
			 case "europeana" {@props = extractEDMProperties($id);}
			}

    	if ($props[0]) {
    	   if (not($props[0] =~ /^\d+?$/)) { # we need integer values (pixels)
             say "#### PROBLEM on width value ".$props[0];
             return undef
            }
         if (not($props[1] =~ /^\d+?$/)) {
             say "#### PROBLEM on height value ".$props[1];
             return undef
            }

    		 # the Gallica API doesn't return the DPI value
    		 if ($hash{"type"} eq "M") {  # different DPI depending on the document types
    		   $facteur= $facteur_imp;}
    		 else {$facteur= $facteur_photo;}

    	   $hash{"largeur"} = int($props[0]*$facteur); # document size in mm
    	   $hash{"hauteur"} = int($props[1]*$facteur); # actually, we take the first page...
				 $hash{"largeurPx"} = int($props[0]); # document size in pixels
    	   $hash{"hauteurPx"} = int($props[1]);
    	   if ($DEBUG) {
    	       say " width: ".$props[0]." - hight: ".$props[1]." (pixels)";
    	       say " width: ".$hash{"largeur"}." - hight: ".$hash{"hauteur"}." (mm)";}
            $hash{"taille"} = int($hash{"largeur"}*$hash{"hauteur"} / $A8) ; # in termes of A8 size
      }
      else {say "#### document dimensions unknown! ####";
            return undef;
              }

    	return 1;
}

sub findPerson {my $chaine=shift;
  if (
#($tmp  =~  m/\w,\s.+(\d+) ?-(\d+)/) or  # motif Stroehlin, Henri (1876-1918) ou (1876?-1918)
		($chaine  =~  m/[A-ZÉ]\w+[\s|,\s]+[A-ZÉ].+(\d+) ?-(\d+)/) or
		($chaine  =~  m/Mme\s/) or
		($chaine  =~  m/Miss\s/) or
		($chaine  =~  m/M\.\s/) ) {
			return 1
		}
	}

############################
# extract the IPTC theme from a string
sub extractIPTC {my $chaine=shift;

      if ($DEBUG) {say " extract IPTC: ".$chaine;}
        $chaine =~ s/ -- / /g;# suppress the --
    	$chaine = escapePunct($chaine); # suppress punctuation
        $chaine =~ s/  / /g;# suppress  double spaces from escapePunct()
    	if ($DEBUG) {say " string: ".$chaine;}
    	# tokenize on space or '
    	my @mots = split(' |\'|’',$chaine);
    	# lemmatise
    	my @motsLem  = $stemmer->stem(@mots);
    	if ($DEBUG) {say "lemmes: ".Dumper(\@motsLem);}
    	# look for a match in the IPCT hash
    	foreach my $m  (@motsLem) {
    	 	if ((length($m) > 2) && ($m =~ /^[a-zA-Zéèêëàâôïîç-]+$/))  {	# if word > 3 characters and alphanumeric
    	 	 	 #if ($DEBUG) {
						 #say "  w: ".$m;}
    	 	 	 ($match) = grep {$_ =~ /\b$m\b/} keys %iptc;	  # \b to start the match at beginning of word and stop at end
    	    if ($match) {
    	    	 if ($DEBUG) {say "-> match: $match"}
    	       return $iptc{$match};
    	       }
            }
          }
   return undef;
}

############################
# extract dimensions + some more info from and ark ID
sub extractGallicaProperties {my $id=shift;

     # cas du multipage :
     # une seule legende :
     # http://gallica.bnf.fr/services/Pagination?ark=btv1b84363424
     # http://oai.bnf.fr/oai2/OAIHandler?verb=GetRecord&metadataPrefix=oai_dc&identifier=ark:/12148/btv1b84363424

     # avec plusieurs légendes :
     # http://gallica.bnf.fr/services/Pagination?ark=btv1b8447273x
     # btv1b10315960d
     # btv1b105256695

     # une page :
     # http://gallica.bnf.fr/services/Pagination?ark=btv1b530158131
     #bpt6k383685v

     # pages de texte
     # http://gallica.bnf.fr/services/Pagination?ark=btv1b10315938r

    # reliure
    #http://gallica.bnf.fr/ark:/12148/btv1b55002864p/f1.planchecontact

    # call API Gallica
    my $url = $urlAPIbnf.$id;
    my $legende1 ;
    my @legendes;
    my @pages;
    my @numeros;
    my @largeurs;
    my @hauteurs;
    my @lines;
    my $ok;

    say "\n  ** calling the Gallica Pagination service: $url";
    #my $reponseAPI = get($url); # get is in LWP::Simple
		$cmd="curl '$url'";
		my $reponseAPI = `$cmd`;
		#say "res: ".$res;
		if ($reponseAPI and index($reponseAPI, "server error") == -1)  {
		  say "... API is responding: ".substr($reponseAPI,0,30)." ...";
			say "-------------------------------------";
     	# test if ToC
     	(my $toc) = do { local $/; $reponseAPI =~ m/$motifToc/s };
     	$hash{"toc"} = $toc;
     	#if ($DEBUG) {say "  ... ToC: ".$toc;}
      # test if OCR
     	(my $ocr) = do { local $/; $reponseAPI =~ m/$motifOcr/s };
     	$hash{"ocr"} = $ocr;
     	#if ($DEBUG) {say "  ... OCR: ".$ocr;}

     	# look for the opening page
     	($pageOuv) = do { local $/; $reponseAPI =~ m/$motifFirst/s };
     	$pageOuv ||= 1; # 1 if no opening paget
      if ($DEBUG) {say "  ... Opening page: ".$pageOuv;}
      # pages order
		 	@pages = do { local $/; $reponseAPI =~ m/$motifOrdre/g };
		 	$nbPages =  scalar @pages;
		 	$hash{"pages"} = $nbPages;
		 	say "  ... Pages number: ".$nbPages ;
      # pages number, dimensions
     	(@numeros ) = do { local $/; $reponseAPI =~ m/$motifNumero/g };
      (@largeurs ) = do { local $/; $reponseAPI =~ m/$motifLargeurBnF/g };
     	(@hauteurs ) = do { local $/; $reponseAPI =~ m/$motifHauteurBnF/g };
    	if ($DEBUG ) {
     					 #say Dumper(\@largeurs);
     					 #say Dumper(\@hauteurs);
     					 #say Dumper(\@numeros);
     			}
     	# test if the data is unconsistent
     	if ((scalar @pages) != (scalar @largeurs)) { # problem!
     			say "#### unconsistent data for document $id: pages number: $nbPages / dimensions number: ".(scalar @largeurs);
     			return undef}

     	# looking for pair of caption/page number
     	@lines = split /\n/, $reponseAPI;
     	foreach my $line (@lines) {
     			#say $line;
     			(my $leg ) = $line =~ m/$motifLeg/;
					if (defined $leg)  {
						$hash{"caption"} = "true";
						$legCourant = $leg;}
     			(my $num ) = $line =~ m/$motifOrdre/;
     			if (defined $num) {
     				if ($DEBUG) {print "$num "}
     			  $numCourant = $num;}
     			if ((defined $legCourant) and  (defined $numCourant)){
     			  say "caption on page: ".$numCourant." : ".substr($legCourant,0,30)."...";
     			  $legendes[$numCourant-1]= $legCourant;
     			 undef $legCourant;undef $numCourant}
     		}

      if ($DEBUG) {
				say "\ncaptions: ".Dumper(\@legendes);
			}

      # common case where we only have one caption (one first page)
     	if (scalar @legendes == 1) {
     			if ($DEBUG)   {say "--> one caption";}
     			$legende1 = escapeXML_OAI($legendes[0]);
     		    if ($legende1 eq $hash{"titre"}) { # if caption== title, throw it away
     		       if ($DEBUG)  {say "--> caption == title"};
     			     undef $legende1;
							 undef $legendes[0];
						   $hash{"caption"} = "false" }
     		}
     	# for some document types, we only keep the opening page
     	if ($type eq "PA")   { # partition
  	            $hash{$pageOuv."_ill_1_w"} = $largeurs[$pageOuv-1];
  	            $hash{$pageOuv."_ill_1_h"} = $hauteurs[$pageOuv-1];
  	            $hash{$pageOuv."_ill_1_coul"} = getColor($id, $pageOuv);
  	        }
  	  elsif (defined $pageExt) { # if we only have a page to consider (getRecordOAI_page)
  	        	$hash{$pageExt."_ill_1_w"} = $largeurs[$pageExt-1];
  	          $hash{$pageExt."_ill_1_h"} = $hauteurs[$pageExt-1];
  	          $hash{$pageExt."_ill_1_coul"} = getColor($id, $pageExt);
  	        }
  	  else{ # std case: we have one illustration per page
     		   for (my $i = 1; $i <= $nbPages; $i++) {
     		   	  # we have to throw away the binding pages: "plat", "dos" keyword
     		      if ((index($numeros[$i-1], "plat ") == -1)
							  and (index($numeros[$i-1], "garde ") == -1)
								and $numeros[$i-1] ne "dos") {
     		  	    $hash{$i."_ill_1_w"} = $largeurs[$i-1]; # en pixels
     		        $hash{$i."_ill_1_h"} = $hauteurs[$i-1];
     		        $ok = 1;
     		        }

    			 # if only one caption,  duplicate the caption everywhere
    		   if (defined ($legende1)) {
    		         if ($DEBUG) {say "duplicated caption";}
    		         $hash{$i."_ill_1_leg"} = $legende1;}
    		   else { # std case
    		  	     $hash{$i."_ill_1_leg"} = escapeXML_OAI($legendes[$i-1]);}

    		   if ($ok) {
     		  	 	# guess the color mode for each illustration
    		  	  if ($couleur eq "inconnu")  {
     		         $hash{$i."_ill_1_coul"} = getColor($id, $i);}
     		      else {$hash{$i."_ill_1_coul"} = $couleur;}
     		    }

     		   }
    		 }
    		return ($largeurs[0],$hauteurs[0]) # return  dimensions of the first page
      }
    else {
          say "\n#### API Gallica Pagination : no response or unknow ID! ###";
          return undef;
    }
}

sub extractEDMProperties {my $id=shift;

    # call the  Europeana API
    my $url = $urlAPIeuropeana.$id.".json?wskey=$cleEuropeana";
    my $legende1 ;
    my @legendes;
    my @pages;
    my @numeros;
    my @largeurs;
    my @hauteurs;
    my @lines;
    my $ok;

    say "\n  ** calling the Europeana Record service: $url";
    #my $reponseAPI = get($url); # get is in LWP::Simple
		$cmd="curl -X GET --header 'Accept: application/json' '$url'";
		my $reponseAPI = `$cmd`;
		if ($reponseAPI and index($reponseAPI, "success\":false") == -1)  {
		  say "... API is responding: ".substr($reponseAPI,0,100)." ...";
			#if ($DEBUG) {say $reponseAPI}
			($couleur)  = do { local $/; $reponseAPI =~ m/$motifCoulEDM/s };
			($iiifCompliant ) = do { local $/; $reponseAPI =~ m/$motifIIIFEDM/s }; # first match
			if ($iiifCompliant) {
				$nbIIIF++;
				my $iiifBase = substr $iiifCompliant, 2; # suppress the first 2 chars
				#my  .= "info.json";
				say " ** IIIF: $iiifBase";
				my $manifest = $iiifBase."info.json";
				my $json = `curl -X GET --header 'Accept: application/json' '$manifest'`;
				if ($DEBUG) {say $json}
				(@largeurs ) = do { local $/; $json =~ m/$motifLargeurEDM/g };
				(@hauteurs ) = do { local $/; $json =~ m/$motifHauteurEDM/g };
				if ($DEBUG) {
								# say Dumper(\@largeurs);
								# say Dumper(\@hauteurs);
						}
				$hash{"1_ill_1_w"} = $largeurs[0]; # en pixels
				$hash{"1_ill_1_h"} = $hauteurs[0];
				$hash{"pages"} = 1; # we handle only image
				$hash{"URLbaseIIIF"} =  $iiifBase;
				if ($couleur) {
							if ($DEBUG) {say $couleur}
							switch ($couleur) {
					 			case "grayscale"		{ $hash{"1_ill_1_coul"} = "gris" }
								case "sRGB"  { $hash{"1_ill_1_coul"} = "coul" }
					 			else { say "#### unknow color mode: $couleur ####"}
						}}
				return ($largeurs[0],$hauteurs[0])
			}
			else {
				say "#### not IIIF compliant! ####";
				return undef}
		}
		else {
          say "\n#### API Europeana Record: no response or unknow ID! ###";
          return undef;
    }
}

############################
# get color mode from the image file
sub getColor {my $id=shift;
	            my $page= shift;

  print "getColor: $page -> ";

	my $file = "/tmp/test.jpg";
	my $url = $urlGallica.$id.".thumbnail";
	#say $url;

	getstore($url, $file);

	my $info = image_info($file);
	#say Dumper ($info);
	if (my $error = $info->{error}) {
     say "Can't parse image info: \n$error";
  }

    #my $color = $info->{SamplesPerPixel};
	my $color = $info->{color_type};
	if ($color eq 'YCbCr') { # cas PNG/JPG
	   $color = $info->{SamplesPerPixel};}

	if ($DEBUG) {say "** color of page $page: ".$color;}
	 switch ($color) {
		case "1"		{say "gris"; return "gris" }
		case "Gray"		{say "gris";  return "gris" }
		case "3"		{say "coul";  return "coul" }
		else		{ say "#### unknow color mode: $color ####";
			return undef }
	}

}


#######################
#    export the metadata
#    cf. bib-XML.pl library

# exportPage($id,$p,$format,$fh);

#######################
#  export the metadata for a page. One illustration per page
sub exportPage {my $id=shift;
	            	my $p=shift;        # page number
								my $format=shift;   # format : xml
	            	my $fh=shift;       # file handler

  if (exists $hash{$p."_filtre"}) {
		if ($DEBUG) {say "page #$p has been filtered";}
	}
	elsif (not exists $hash{$p."_ill_1_w"})  {  # don't export pages with no illustration
    if ($DEBUG) {say "page #$p: filtered illustration";}
	}
	else {
	  if ($DEBUG) {say "... exporting page #$p"; }
	  $nbTotIlls++;
	  %atts = ("ordre"=> $p);
  	  writeEltAtts("page",\%atts,$fh);
  	  writeElt("blocIllustration",1,$fh);  #  one illustration per page
  	  writeOpenElt("ills",$fh);
			if (defined ($coul = $hash{$p."_ill_1_coul"}))  {
  	  		%atts =("n"=>$p."-1",  "x"=>1, "y"=>1, "w"=>$hash{$p."_ill_1_w"}, "h"=>$hash{$p."_ill_1_h"},
  	  		"taille"=>$hash{"taille"}, "couleur"=>$coul)} # n has this format : n° page-n° ill  (here n° ill = 1)}
					else {%atts =("n"=>$p."-1",  "x"=>1, "y"=>1, "w"=>$hash{$p."_ill_1_w"}, "h"=>$hash{$p."_ill_1_h"},
  	  		"taille"=>$hash{"taille"})}
  	  writeEltAtts("ill",\%atts,$fh);
  	  if (defined $genreDefaut) {
    		      %atts = ("CS"=> "1", "source"=>"hm");    # confidence value = 1, source= human
  	  	  	  writeEltAtts("genre",\%atts,$fh);
  	  	  	  print {$fh} $genreDefaut;
  	  	  	  writeEndElt("genre",$fh); }
  	  elsif ($genre ne "inconnu") {
  	  	  	  %atts = ("CS"=> "0.95", "source"=>"md");  # confidence = 0.95 (based on the document metadata)
  	  	  	  writeEltAtts("genre",\%atts,$fh);
  	  	  	  print {$fh} $genre;
  	  	  	  writeEndElt("genre",$fh);
  	  	      }
  	  if (defined ($IPTCDefaut)) {
				%atts = ("CS"=> "1", "source"=>"md");
				writeEltAtts("theme",\%atts,$fh);
				print {$fh} $IPTCDefaut;
				writeEndElt("theme",$fh)}
  	  elsif (defined($theme)) {
		 			%atts = ("CS"=> "0.8", "source"=>"md");  # confidence = 0.8 (based on the IPTC words network)
					writeEltAtts("theme",\%atts,$fh);
					print {$fh} $theme;
					writeEndElt("theme",$fh)}
  	 if (defined $personne) {  	  	# if the illustration is a portrait, we add a classification tag
  	  	 %atts = ("CS"=>"1.0", "lang"=>"en", "source"=>"md");
  	     writeEltAtts("contenuImg",\%atts,$fh);
  	     print {$fh} "person";
  	  	 writeEndElt("contenuImg",$fh);
			 	 if ($personne ne "person") {
					 writeEltAtts("contenuImg",\%atts,$fh);
	  	     print {$fh} $personne;
	  	  	 writeEndElt("contenuImg",$fh);
				 }
			 }
		 if (@tags) {  	  	# if some tags exist
		   foreach $t (@tags) {
		 		 %atts = ("CS"=> "1.0", "lang"=>"en", "source"=>"hm");
		 		 writeEltAtts("contenuImg",\%atts,$fh);
		 		 print {$fh} $t;
		 		 writeEndElt("contenuImg",$fh);}
			 }
			if (@sujets and $sujets2tags) {  	  	# subjects may be considered as tags
  		   foreach $t (@sujets) {
  		 		 %atts = ("CS"=> "1.0", "lang"=>"fr", "source"=>"md");
  		 		 writeEltAtts("contenuImg",\%atts,$fh);
  		 		 print {$fh} $t;
  		 		 writeEndElt("contenuImg",$fh);}
  			 }
  	 # caption
  	 $tmp = $hash{$p."_ill_1_leg"};
  	 if (defined ($tmp) and (length($tmp)>0)) {writeElt("leg",$tmp,$fh);}
  	 # duplicate the document title in the illustration title (to be consistent with other document types (newspapers...)
  	 writeElt("titraille",$hash{"titre"},$fh);

  	 writeEndElt("ill",$fh);
  	 writeEndElt("ills",$fh);
  	 writeEndElt("page",$fh);
  	}
 }
