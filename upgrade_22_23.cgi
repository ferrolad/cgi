#!/usr/bin/perl
# SQL Upgrade script from XFS Pro
use strict;
use XFileConfig;
use CGI::Carp qw(fatalsToBrowser);
use DBI;
use DataBase;

my $db = DataBase->new();
die"Can't connect to DB" unless $db;

open(FILE,"upgrade_22_23.sql")||die("Can't open sql");
my $sql;
$sql.=$_ while <FILE>;
$sql=~s/CREATE TABLE/CREATE TABLE IF NOT EXISTS/gis;

print"Content-type:text/html\n\n";

for(grep{length($_)>3} split(';',$sql))
{
  eval { $db->Exec($_) };
}

print "<br><br>DONE.";
