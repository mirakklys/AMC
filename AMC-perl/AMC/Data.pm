# -*- perl -*-
#
# Copyright (C) 2011 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Data;

# AMC::Data handles data storage management for AMC. An AMC::Data can
# load several "modules" which are SQLite database files in a common
# directory $dir, with their associated methods to get/set data.

use Module::Load;
use AMC::Basic;
use DBI;

sub new {
    my ($class,$dir,%oo)=@_;

    my $self={
	'directory'=>$dir,
	'timeout'=>300000,
	'dbh'=>DBI->connect("dbi:SQLite:",undef,undef,
			    {AutoCommit => 0,
			     RaiseError => 0,
			    }),
	'modules'=>{},
	'on_error'=>'stdout,stderr,die',
    };

    for(keys %oo) {
	$self->{$_}=$oo{$_} if(exists($self->{$_}));
    }

    $self->{'dbh'}->sqlite_busy_timeout($self->{'timeout'});
    $self->{'dbh'}->{sqlite_unicode}=1;

    bless($self,$class);

    $self->{'dbh'}->{HandleError}=sub {
      $self->sql_error(shift);
    };
    return $self;
}

# SQL errors...

sub sql_error {
  my ($self,$e)=@_;
  my $s="SQL ERROR: $e\nSQL STATEMENT: ".$DBI::lasth->{Statement};
  debug "$s";
  print "$s\n" if($self->{'on_error'} =~ /\bstdout\b/);
  print STDERR "$s\n" if($self->{'on_error'} =~ /\bstderr\b/);
  die "*SQL*" if($self->{'on_error'} =~ /\bdie\b/);
}

# directory returns the directory where databases files are stored.

sub directory {
    my ($self)=@_;
    return($self->{'directory'});
}

# dbh returns the DBI object corresponding to the SQLite session with
# required modules attached.

sub dbh {
    my ($self)=@_;
    return($self->{'dbh'});
}

# begin_transaction begins a transaction in immediate mode, to be used
# to eventually write to the database.

sub begin_transaction {
    my ($self,$key)=@_;
    $key='----' if(!$key);
    debug_and_stderr "WARNING: opened transaction $self->{'data'}->{'trans'}"
      if($self->{'trans'});
    $self->sql_do("BEGIN IMMEDIATE");
    $self->{'trans'}=$key;
}

# begin_read_transaction begins a transaction for reading data.

sub begin_read_transaction {
    my ($self,$key)=@_;
    $key='----' if(!$key);
    debug_and_stderr "WARNING: opened transaction $self->{'data'}->{'trans'}"
      if($self->{'trans'});
    $self->sql_do("BEGIN");
    $self->{'trans'}=$key;
}

# end_transaction end the transaction.

sub end_transaction {
    my ($self,$key)=@_;
    $key='----' if(!$key);
    debug_and_stderr "WARNING: closing transaction $self->{'trans'} declared as $key"
      if($self->{'trans'} ne $key);
    $self->sql_do("COMMIT");
    $self->{'trans'}='';
}

# sql_quote($string) can be used to quote a string before including it
# in a SQL query.

sub sql_quote {
    my ($self,$string)=@_;
    return $self->{'dbh'}->quote($string);
}

# sql_do($sql,@bind) executes the SQL query $sql, replacing ? by the
# elements of @bind.

sub sql_do {
    my ($self,$sql,@bind)=@_;
    debug_and_stderr "WARNING: sql_do with no transaction -- $sql" if(!$self->{'trans'});
    $self->{'dbh'}->do($sql,{},@bind);
}

# sql_tables($tables) gets the list of tables matching pattern $tables.

sub sql_tables {
    my ($self,$tables)=@_;
    return($self->{'dbh'}->tables('%','%',$tables));
}

# require_module($module) loads the database file corresponding to
# module $module (found in the data directory), and associated methods
# defined in AMC::DataModule::$module perl package.

sub require_module {
    my ($self,$module)=@_;
    if(!$self->{'modules'}->{$module}) {
	my $filename=$self->{'directory'}."/".$module.".sqlite";
	if(! -f $filename) {
	    debug("Creating unexistant database file for module $module...");
	}

	debug "Connecting to database $module...";
	$self->{'dbh'}->{AutoCommit}=1;
	$self->sql_do("ATTACH DATABASE ".$self->sql_quote($filename)." AS $module");
	$self->{'dbh'}->{AutoCommit}=0;

	debug "Loading perl module $module...";
	load("AMC::DataModule::$module");
	$self->{'modules'}->{$module}="AMC::DataModule::$module"->new($self);

	debug "Module $module loaded.";
    }
}

# module($module) returns the module object associated to module
# $module (call the methods from module $module from this object).

sub module {
    my ($self,$module)=@_;
    $self->require_module($module);
    return($self->{'modules'}->{$module});
}

1;
