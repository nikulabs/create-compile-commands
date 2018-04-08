#!/usr/bin/perl
# This script is written in perl for performance reasons, not for portability.
# Requires several non-default perl modules, and an external tool, "jq".

use feature 'state';
use strict;
use warnings;
use Cwd 'realpath';
use File::Copy;
use File::Spec;
use File::Tee qw(tee);
use File::Temp qw(tempfile);

our $KEEP_ALL=1;

my $tempOutput = File::Temp->new();

sub transformInput;
sub buildJSONEntry;
sub prependCommaForMultipleEntries;

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
print qx(jq --slurp "unique_by(.file)" $tempOutput ) || die "Unable to make entries unique";
close $tempOutput;

sub transformInput {
  my( $command, $directory ) = @_;
  chomp($command);
  $command =~ tr/"//d;  #Don't fail if there aren't any quotes to remove
  $command =~ tr/\\//d; #Don't fail if there aren't any escapes to remove
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

sub prependCommaForMultipleEntries {
  my $comma="";
  state $counter=0;
  if ( $counter gt 0 ) {
    $comma = ",\n";
  }
  $counter = 1;
  return $comma;
}
