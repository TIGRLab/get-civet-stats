#! /usr/bin/env perl

use strict;
#use Parallel::Loops;
use File::Basename;
use File::Temp qw/ tempdir /;
use Cwd 'abs_path';

my $me     = &basename($0);
my $scriptpath = &dirname(abs_path($0));

#Setup temp file directory
my $tmpdir = &tempdir("$me-XXXXXXXXXXX", TMPDIR => 1, CLEANUP => 1);

#Setup input and output
my $input_dir = shift or die "Need path to CIVET output \n";
my $output_file = shift or die "Need path to output file \n";

#Numbered labels in lpba40
my @labels = qw(27 21 5 25 9 15 3 7 11 13 23 19 69 1 17 57 29 59 61 63 65 67 49 51 53 43 45 47 55 79 81 85 89 83 87 39 31 33 35);

#Names associated with @labels
my @structures = qw(REC
OLF
ORBsup
ORBsupmed
ORBmid
ORBinf
SFGdor
MFG
IFGoperc
IFGtriang
SFGmed
SMA
PCL
PreCG
ROL
PoCG
Ins
SPG
IPL
SMG
ANG
PCUN
SOG
MOG
IOG
CAL
CUN
LING
FFG
HES
STG
MTG
ITG
TPOsup
TPOmid
PHG
ACG
DCG
PCG
);

#Define location of aal label minc files
my $left_model =  "/projects/melissa/current/Scripts/CIVET/aal/aal_L.mnc";
my $right_model =  "/projects/melissa/current/Scripts/CIVET/aal/aal_L-flip.mnc";

my @subjects = split(/\n/, `ls -1 $input_dir`);
#@subjects = grep { $_ != "QC" } @subjects;
#@subjects = grep { $_ != "References.txt" } @subjects;

chomp(@subjects);
print "----\n";
print @subjects;
print "----\n";

#Build Header of Output File
open(FILE, ">$output_file");
print FILE "Subject_ID";
foreach(@structures){
    print FILE ",${_}_left_CT";
    print FILE ",${_}_left_SA"; 
    print FILE ",${_}_right_CT";
    print FILE ",${_}_right_SA";
}
print FILE "\n";

#my $maxProcs = 4;
#my $pl = Parallel::Loops->new($maxProcs);

#my @output;
#$pl->share(\@output);

#$pl -> foreach(\@subjects , sub {
#    print $_;
#});

foreach(@subjects) {
    my $subject = $_;
    if (($subject eq 'QC') or ($subject eq 'References.txt')) {
       next;
    }
    print "Processing $subject\n";
    my $output = $subject;    
    chomp(my $obj_left_file = `ls -1 ${input_dir}/${subject}/surfaces/*gray_surface_rsl_left_81920.obj`);
    chomp(my $obj_right_file =  `ls -1 ${input_dir}/${subject}/surfaces/*gray_surface_rsl_right_81920.obj`);
    chomp(my $ct_left_file = `ls -1 ${input_dir}/${subject}/thickness/*native_rms_rsl_tlink_20mm_left.txt`);
    chomp(my $ct_right_file = `ls -1 ${input_dir}/${subject}/thickness/*native_rms_rsl_tlink_20mm_right.txt`);
    chomp(my $sa_left_file = `ls -1 ${input_dir}/${subject}/surfaces/*mid_surface_rsl_left_native_area_40mm.txt`);
    chomp(my $sa_right_file = `ls -1 ${input_dir}/${subject}/surfaces/*mid_surface_rsl_right_native_area_40mm.txt`);
    chomp(my $nonlin_transform_file = `ls -1 ${input_dir}/${subject}/transforms/nonlinear/*nlfit_It.xfm`);
    do_cmd('mincresample',
        $left_model, "${tmpdir}/${subject}_left_model.mnc",
        '-clobber',
        '-transformation', $nonlin_transform_file,
        '-invert',
        '-use_input_sampling',
        '-nearest_neighbour'
    );
    do_cmd('mincresample',
        $right_model, "${tmpdir}/${subject}_right_model.mnc",
        '-clobber',
        '-transformation', $nonlin_transform_file,
        '-invert',
        '-use_input_sampling',
        '-nearest_neighbour'
    );
    my $i = 0;
    foreach(@labels) {
        #Extract left and right labels into separate file 
        do_cmd('minclookup', 
            '-clob',
            '-lut_string', "${_} 1",
            '-discrete',
            "${tmpdir}/${subject}_left_model.mnc",
            "${tmpdir}/${subject}_left_${structures[$i]}.mnc");
        do_cmd('minclookup', 
            '-clob',
            '-lut_string', "${_} 1",
            '-discrete',
            "${tmpdir}/${subject}_right_model.mnc",
            "${tmpdir}/${subject}_right_${structures[$i]}.mnc");

        #Construct overlap of label and object file
        do_cmd('volume_object_evaluate',
            '-nearest_neighbour', 
            "${tmpdir}/${subject}_left_${structures[$i]}.mnc",
            $obj_left_file, 
            "${tmpdir}/${subject}_left_${structures[$i]}_mask.txt");
        do_cmd('volume_object_evaluate',
            '-nearest_neighbour', 
            "${tmpdir}/${subject}_right_${structures[$i]}.mnc",
            $obj_right_file, 
            "${tmpdir}/${subject}_right_${structures[$i]}_mask.txt");
        #Read in mask files
        my @left_mask = split(/\n/, `cat ${tmpdir}/${subject}_left_${structures[$i]}_mask.txt`);
        my @right_mask = split(/\n/, `cat ${tmpdir}/${subject}_right_${structures[$i]}_mask.txt`);
        my @left_ct = split(/\n/, `cat ${ct_left_file}`);
        my @right_ct = split(/\n/, `cat ${ct_right_file}`);
        my @left_sa = split(/\n/, `cat ${sa_left_file}`);
        my @right_sa = split(/\n/, `cat ${sa_right_file}`);
        my $left_count = 0;
        my $right_count = 0;
        my $left_ct_total = 0;
        my $left_sa_total = 0;
        my $right_ct_total = 0;
        my $right_sa_total = 0;
        my $j = 0;  

        foreach(@left_mask){
            if ($_ > 0.5) {
                $left_count++;
                $left_ct_total = $left_ct_total + $left_ct[$j]; 
                $left_sa_total = $left_sa_total + $left_sa[$j]
            }
            $j++;
        }
        $output = $output . "," . $left_ct_total/$left_count . "," . $left_sa_total;
        $j = 0;
        foreach(@right_mask){
            if ($_ > 0.5) {
                $right_count++;
                $right_ct_total = $right_ct_total + $right_ct[$j]; 
                $right_sa_total = $right_sa_total + $right_sa[$j];
            }
            $j++;
        }
        $output = $output . "," . $right_ct_total/$right_count . "," . $right_sa_total;

        $i++;

    }
    print FILE $output;
    print FILE "\n";
    unlink glob "${tmpdir}/${subject}*";
}


sub do_cmd{
    print "@_ \n";
    system(@_) == 0 or die;
}

