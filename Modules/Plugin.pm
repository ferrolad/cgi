package Plugin;

use strict;
use warnings;
use XFSConfig;
use Encode qw/encode decode/;
use Exporter ();
@Plugin::ISA    = qw(Exporter);
@Plugin::EXPORT = qw($c $browser $log);
use vars qw($c $browser $log);

our $options = {
	plugin_id=>999,
	plugin_prefix=>'',
        name=>'Plugin',
        domain=>'',
};

our $tmpfile;

sub new {
        my $class = shift;                                                                                                                                                       
        my $self = shift;                                                                                                                                                        
        bless $self, $class;                                                                                                                                                     
        return $self;                                                                                                                                                            
}                                                                                                                                                                                
sub options {return shift}
sub PluginID {my $self = shift;return $self->options()->{plugin_id}};
sub name {my $self = shift;return $self->options()->{name}};
sub domain {my $self = shift;return $self->options()->{domain}}
sub login {
        my $self = shift;
        my $account = shift;
        my $prefix = shift;
        $self->{prefix} = $prefix;
        $self->{action} = 'login';
        $self->{n} = 0;
        return 1;
}
sub clear {
        my $self = shift;
        if($self->{request}) {
                $self->{request}->clear();
                $self->{request} = undef;
        } 
        if($self->{response}) {
                $self->{response}->clear();
                $self->{response} = undef;
        }
        if($self->{content}) {
                $self->{content} = undef;
        }
}
sub upload_stat {
	my $self = shift;
	my $uploaded = shift;
	#if($uploaded && $self->{task_id} && $self->{ses}) {
	#	$self->{ses}->Exec('UPDATE tasks SET uploaded = ? WHERE id = ?', $uploaded, $self->{task_id});
	#}
}
sub up_file {
	my $self = shift;
	my $req = shift;
	my $gen = $req->content();
	my $uploaded = 0;
	$req->content( sub {my $chunk = &$gen();$self->upload_stat($uploaded);$uploaded+=length($chunk) if($chunk);return $chunk;} ); 
	$self->request($req);

}
sub is_broken {
	my $self = shift;
	my $link = shift;
	return 0;
}
sub direct_download {
	my $self = shift;
	my $req = shift;
	my $link = shift;
	my $prefix = shift;
	my $update_stat = shift;
	my $retries = 0;
	my $ct;
	my $file = undef;
	my $flength = 0;
	RETR: {
	my @done = (0,0,0);
	my $perc = 0;
	my $f;
	my $resume = 0;
	my $callback =     sub {
		my $str = shift;
		my $res = shift;
		unless ($f) {
			$file = undef if (($res->code==200));
		};
                #print $res->code.":".$res->as_string."\n";
#		Filename detection
		unless ($file) {
                    #print"ok101\n";
			my $cd = $res->header("Content-Disposition");
			$ct = $res->header("Content-Type");
			if ($cd && $cd =~ /filename\s*=\s*(.+?)(;|\z)/) {
				$file = $1;
				$file =~ s/;$//;
				$file =~ s/^([\"\'])(.*)\1$/$2/;
				$file =~ s,.*[\\/],,;  # basename
				if($cd =~/\"(.*?)\"/) {
					$file = $1;
				}
				$file =~ s/\s//g;
				$file  = decode('MIME-Header', $file);

			} 
			unless ($file) {
				my $req = $res->request;  # now always there
				$ct = $res->content_type;
				my $rurl = $req ? $req->url : $link;
				$file = ($rurl->path_segments)[-1];
				if (!defined($file) || !length($file)) {
					$file = "index";
					my $suffix = media_suffix($res->content_type);
					$file .= ".$suffix" if $suffix;
				}
				$file =~ s/\s//g;
			} 
			$flength = $res->content_length;
			print STDERR "filesize: $flength ($tmpfile)\n" if($flength);
			#$log->write(2,"file=$file");
                        #print STDERR "ok11:$tmpfile\nfile:$file\n";
			open $f, ">$tmpfile" or die $!;
			binmode $f;
		} 
		print $f $str;
		$done[0]+=length($str);
		$done[1]+=length($str);
		$perc = 0;
		if ($flength) {
			$perc= $done[0]/($flength/100);
			$done[2]+=length($str);
			#&$update_stat($flength, $done[2], $file) if($update_stat && $ct !~ /html/);
                        &$update_stat($str, $res) if($update_stat && $ct !~ /html/);
		};
	};
        #print"ok1";
	my $res = $browser->request($req, $callback);
        #print"ok2:\n".$res->as_string;
        #print $browser->
	$req->remove_header('Range') if (($resume) && ($res->is_error));
	if ($f) {
		close($f);
		return {filename=>$file, filesize=>$flength, type=>$ct, resp => $res};
	}
	}    
    return {filename=>$file, filesize=>$flength, type=>$ct};
}


#-----------------Browser-----------------
sub request {
        my $self = shift;
        my $req = shift;
        my $n = shift;
        $n||=$self->{n}||=0;
        $self->{n} = $n;
        $self->{request} = $req;
	$self->{prefix}||=time;
        my $n0 = 0;
#       my $r;
        A: {
                $n0++;
                $self->{response} = $browser->request($req);
                redo A if($self->{response}->code == 500 && $n0<3);
        }
	if($c->{save_html_results}) {
        	open FD, "> $c->{cgi_dir}/logs/$self->{prefix}\_".$self->options()->{name}."\_$self->{action}$n.html";
	        print FD $self->{request}->as_string();
	        print FD $self->{response}->content();
	        print FD $self->{response}->as_string();
        	close FD;
	}
        $log->write(2,$self->{response}->status_line) if($self->{action} eq 'login' && !$self->{response}->is_success  && $self->{response}->code !=302 && $self->{response}->code != 301);
        $self->{content} = $self->{response}->content();
#        $log->write(1, "writing log file $self->{prefix}\_".$self->options()->{name}."\_$self->{action}$n.html");
        $self->{n}++;
        return $self->{response};
}

sub get {
	my $self = shift;
	my $url = shift;
	my $n = shift;
	$n||=$self->{n}||=0;
	$self->{n} = $n;
	$self->{prefix}||=time;
	$self->{content} = $self->{response} = undef;
	my $n0 = 0;
	A: {
	        $n0++;
	        $self->{response} = $browser->get($url);
	        redo A if($self->{response}->code == 500 && $n0<3);
	}
	if($c->{save_html_results}) {
		open FD, "> $c->{cgi_dir}/logs/$self->{prefix}\_".$self->options()->{name}."\_$self->{action}$n.html";
		my $content = $self->{response}->as_string();
		print FD "$url\n";
		print FD $content;
		close FD;
	}
	$log->write(2,$self->{response}->status_line) if($self->{action} eq 'login' && !$self->{response}->is_success  && $self->{response}->code !=302 && $self->{response}->code !=301);
	$self->{content} = $self->{response}->content();
	$self->{n}++;
	return $self->{response};
}

sub getHT {
        my $self = shift;
        my $r = $self->get(@_);
        $log->write(2,$r->status_line) if($self->{action} eq 'login' && !$r->is_success  && $r->code !=302 && $r->code !=301);
        my $h = HTML::TreeBuilder->new_from_content($self->{content});
        $h->ignore_unknown(0);
        $h = $h->elementify();
        return $h;
}

sub requestHT {
        my $self = shift;
        my $r = $self->request(@_);
        $log->write(2, $r->status_line) if($self->{action} eq 'login' && !$r->is_success  && $r->code !=302 && $r->code != 301);
        my $h = HTML::TreeBuilder->new_from_content($self->{content});
        $h->ignore_unknown(0);
        $h = $h->elementify();
        return $h;
}

sub debug_print {
        my $self = shift;
        my $text = shift;
}

1;
