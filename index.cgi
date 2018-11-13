#!/usr/bin/perl -X
use strict;
use lib '.';
use XFileConfig;
use Engine::Core;
use CGI::Carp qw(fatalsToBrowser);
use Log;

Log->new(filename => 'index.log');

Engine::Core::run();
