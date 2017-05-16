#!/usr/bin/perl -X
use strict;
use XFileConfig;
use Session;
use CGI::Carp qw(fatalsToBrowser);
use lib '.';

use index_dl;
&index_dl::run();
