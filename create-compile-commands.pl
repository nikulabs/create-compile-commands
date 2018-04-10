#!/usr/bin/perl
# This script is written in perl for performance reasons, not for portability.
# Requires several non-default perl modules, and an external tool, "jq".

use strict;
use warnings;
use Cwd 'realpath';
use File::Spec;
use File::Temp qw(tempfile);

sub transformInput;
sub buildJSONEntry;

my $tempOutput = File::Temp->new();

my $makeOutput = qx(make -n -B);
my $dirChangeRegex = "^make\[[0-9]+\]: Entering directory";
my $compileCommandRegex = "g(\\+\\+|cc) -c";

my $currentDirectory;

foreach my $line (split /[\r\n]+/, $makeOutput) {
  if ( $line =~ /$dirChangeRegex/ ) {
    $currentDirectory = $1 if ($line =~ /'(.*?)'/);
  }
  if ( length( $currentDirectory ) and $line =~ /$compileCommandRegex/ ) {
    my @cleanInput = transformInput( $line, $currentDirectory );
    my $jsonEntry = buildJSONEntry( @cleanInput );
    print $tempOutput $jsonEntry || die "Could not print entry: $!";
  }
}

$tempOutput->flush;
print qx(jq --slurp 'unique_by(.file) | [.[] | select(.file | contains("moc_") | not)]' $tempOutput ) || die "Unable to make entries unique";
close $tempOutput;

sub transformInput {
  my( $command, $directory ) = @_;
  chomp($command);
  $command =~ tr/\\//d; #Remove escapes on thirdparty paths, why are these here?
  $command =~ s/"/\\\\\\"/g;  #Add escapes to for defines that should be strings
  my @removeEcho = split("&&", $command);
  $command = $removeEcho[-1]; #Remove last in case there wasn't an echo
  $command =~ s/\s+//;
  my $fileInCommand = ( split ' ', $command )[ -1 ] || die "Could not get file name $!";
  my $filePath = File::Spec->catfile( $directory, '/', $fileInCommand ) || die "Could not build file path $!";
  my $canonFile = realpath( $filePath ) || die "Could not get canonical path $!";
  return( $command, $directory, $canonFile );
}

sub buildJSONEntry {
  my( $command, $directory, $file) = @_;
  my $entry = "{\n\"command\": \"$command\"," .
               "\n\"directory\": \"$directory\"," .
               "\n\"file\": \"$file\"\n}\n";
  return $entry;
}
