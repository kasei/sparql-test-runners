#!/usr/bin/env perl

use 5.020;
use strict;
use warnings;
use Attean;
use URI;
use JSON qw(decode_json);
use Attean::RDF qw(iri blank literal quad);
use LWP::UserAgent;
use HTTP::Request;
use HTTP::Status;
use Test::More;
use File::Spec;
use Text::Table;
use Data::Dumper;
use Encode qw(encode encode_utf8);
use Test::Attean::W3CManifestTestSuite;
use Getopt::Long;

my $rdf_type		= iri('http://www.w3.org/1999/02/22-rdf-syntax-ns#type');
my $Manifest		= iri('http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#Manifest');
my $mf_name			= iri('http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#name');
my $entries			= iri('http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#entries');
my $mf_requires		= iri('http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#requires');
my $mf_include		= iri('http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#include');
my $requests		= iri('http://www.w3.org/2011/http#requests');
my $authority		= iri('http://www.w3.org/2011/http#connectionAuthority');
my $mf_action		= iri('http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#action');
my $absolutePath	= iri('http://www.w3.org/2011/http#absolutePath');
my $methodName		= iri('http://www.w3.org/2011/http#methodName');
my $ht_body			= iri('http://www.w3.org/2011/http#body');
my $ht_headers		= iri('http://www.w3.org/2011/http#headers');
my $cnt_encoding	= iri('http://www.w3.org/2011/content#characterEncoding');
my $cnt_chars		= iri('http://www.w3.org/2011/content#chars');
my $ht_fieldName	= iri('http://www.w3.org/2011/http#fieldName');
my $ht_fieldValue	= iri('http://www.w3.org/2011/http#fieldValue');
my $ht_resp			= iri('http://www.w3.org/2011/http#resp');
my $expectedBoolean	= iri('http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#expectedBoolean');
my $expectedFormat	= iri('http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#expectedFormat');
my $expectedStatus	= iri('http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#expectedStatus');
my $mf_expectation	= iri('http://www.w3.org/2001/sw/DataAccess/tests/test-manifest#expectation');
my $ut_graphData	= iri('http://www.w3.org/2009/sparql/tests/test-update#graphData');
my $ut_graph		= iri('http://www.w3.org/2009/sparql/tests/test-update#graph');
my $rdfs_label		= iri('http://www.w3.org/2000/01/rdf-schema#label');

if (scalar(@ARGV) < 2) {
	usage();
	exit(1);
}

sub usage {
	print <<"END";

Usage: $0 [OPTIONS] http://endpoint/sparql [test-pattern]

Run the SPARQL Protocol tests against the specified endpoint.
If [test-pattern] is given, only runs tests whose IRI match the given regex pattern.

OPTIONS:

  -v               Emit verbose logging.

END
}

my $verbose			= 0;
my $list			= 0;
my $manifest		= 'manifest.ttl';

my $ok	= GetOptions(
			"manifest=s"	=> \$manifest,
            "list"			=> \$list,
            "verbose"		=> \$verbose,
        );

unless ($ok) {
	usage();
	exit(1);
}

my $endpoint	= shift;
my $pattern		= shift // '';

my $euri		= URI->new($endpoint);
$euri->fragment(undef);
$euri->query(undef);
$endpoint		= $euri->as_string;

warn "Endpoint: $endpoint\n" if ($verbose);

my $graph		= iri('http://graph-name/');
my ($model, @manifests)	= load_manifests($manifest, $graph);

my $ua		= LWP::UserAgent->new();
drop_all($ua, $endpoint);
run_tests(\@manifests, $ua, $list, $verbose);
exit if ($list);
done_testing();

sub load_manifests {
	my $manifest	= shift;
	my $graph		= shift;
	my $abs			= File::Spec->rel2abs( $manifest ) ;
	my $store		= Attean->get_store('Memory')->new();
	my $model		= Attean::MutableQuadModel->new( store => $store );
	
	$model->load_urls_into_graph($graph, iri('file://' . $abs));
	my ($m)				= $model->subjects($rdf_type, $Manifest)->elements;
	my @manifests	= ($m);
	my ($include_head)	= $model->objects($m, $mf_include)->elements;
	my @includes		= $model->get_list($graph, $include_head)->elements;
	push(@manifests, @includes);
	$model->load_urls_into_graph($graph, @includes);
	warn $model->size . " triples loaded from manifest(s)\n" if ($verbose);
	return ($model, @manifests);
}

sub drop_all {
	my $ua	= shift;
	my $prot_endpoint	= shift;
	# clear dataset
	my $resp	= $ua->post($prot_endpoint, {update => 'DROP ALL'});
	unless ($resp->is_success) {
		warn "POST failed to endpoint: $endpoint";
		warn '- HTTP response: ' . $resp->as_string;
		die 'Failed to POST to SPARQL endpoint: ' . $resp->status_line;
	}
}

sub run_tests {
	my $manifests		= shift;
	my $ua				= shift;
	my $list			= shift;
	my $verbose			= shift;
	my @manifests	= @{ $manifests };
	warn "Pattern: $pattern\n" if ($verbose and $pattern);
	foreach my $m (@manifests) {
		my ($obj)	= $model->objects($m, $entries)->elements;
		my @tests	= $model->get_list($graph, $obj)->elements;
		warn scalar(@tests) . " tests in manifest\n" if ($verbose);
		TEST: foreach my $test (@tests) {
			if ($pattern) {
				next unless ($test->value =~ /$pattern/);
			}
			my ($name)		= $model->objects($test, $mf_name)->elements;
			if ($list) {
				say sprintf("%-75s\t%s", $name->value, $test->value);
				next;
			}
			subtest $test->value => sub {
				my $testname	= $name->value;
				warn "============================================= $testname =============================================\n" if ($verbose);
				diag("Test name: " . $name->value);
				run_test($ua, $endpoint, $model, $test, $verbose);
			};
		}
	}
}

sub make_request {
	my $endpoint	= shift;
	my $model		= shift;
	my $req			= shift;
	my $auth_v		= shift;
	my $real_auth	= shift;
	my ($path)		= $model->objects($req, $absolutePath)->elements;
	my $pathuri		= new URI($path->value);
	my ($method)	= $model->objects($req, $methodName)->elements;
	my ($body)		= $model->objects($req, $ht_body)->elements;
	my ($headers)	= $model->objects($req, $ht_headers)->elements;

	my $m			= HTTP::Request->new();
	$m->method($method->value);
	my $uri	= new URI($endpoint);
# if GSP tests:
# 	$uri->path($pathuri->path);
	$uri->query($pathuri->query);
	
	my $uri_v	= $uri->as_string;
	
	# fixup
	$uri_v	=~ s/$auth_v/$real_auth/e;

	
	$m->uri(URI->new($uri_v));
	if ($body) {
		my ($content)		= $model->objects($body, $cnt_chars)->elements;
		my ($encoding)		= $model->objects($body, $cnt_encoding)->elements;

		# fixup
		$content	=~ s/$auth_v/$real_auth/e;

		my $bytes			= encode($encoding->value, $content->value);
		$m->content($bytes);
	}
	
	my @headers	= $model->get_list($graph, $headers)->elements;
	foreach my $h (@headers) {
		my ($key)		= $model->objects($h, $ht_fieldName)->elements;
		my ($value)		= $model->objects($h, $ht_fieldValue)->elements;
		$m->header($key->value => $value->value);
	}
	return $m;
}

sub dump_dataset {
	my $endpoint	= shift;
	my $resp	= $ua->post($endpoint, {query => 'SELECT * WHERE { { GRAPH ?g { ?s ?p ?o } } UNION { ?s ?p ?o } }'}, 'Accept' => 'application/sparql-results+json');
	my $body	= $resp->decoded_content;
	my $j		= decode_json($body);
	my $r		= $j->{results}{bindings};
	my $tb		= Text::Table->new(qw(s p o g));
	my @rows;
	foreach my $r (@$r) {
		push(@rows, [map { $r->{$_}{'value'} } qw(s p o g)]);
	}
	$tb->load(@rows);
	say $tb;
}

sub validate_response {
	my $endpoint	= shift;
	my $model	= shift;
	my $test	= shift;
	my $name	= $test->value;
	my $req		= shift;
	my $m		= shift;
	my $auth_v		= shift;
	my $real_auth	= shift;
	
	warn "Validating response..." if ($verbose);
	
	my ($resp)	= $model->objects($req, $ht_resp)->elements;
	unless ($resp) {
		return fail('No expected response data for test');
	}

	my (@expected_status)	= $model->objects($resp, $expectedStatus)->elements;
	if (scalar(@expected_status)) {
		my %ok				= map { $_ => 1 } map { $_->value } @expected_status;
		my $code			= $m->code;
		my $digit			= int($code / 100);
		my $actual_class_iri		= "http://www.w3.org/2011/http-statusCodes#StatusCode${digit}xx";
		my $message					= status_message($code);
		$message					=~ s/ //g;
		my $actual_iri				= "http://www.w3.org/2011/http#$message";
		if (exists $ok{$actual_class_iri}) {
			pass("status code matches class ${digit}xx")
		} elsif (exists $ok{$actual_iri}) {
			pass("status code matches ($code)")
		} else {
			fail("got status code: " . $m->status_line . ' but expecting one of: ' . join(',', keys %ok))
		}
	}
	my ($expected_format)	= $model->objects($resp, $expectedFormat)->elements;
	if ($expected_format) {
		my $ct	= $m->header('Content-Type');
		my $expected	= $expected_format->value;
		if ($expected eq 'tabular') {
			like($ct, qr#^application/sparql-results[+](json|xml)|text/csv|text/tab-separated-values#, "expected tabular result but got $ct");
		} elsif ($expected eq 'boolean') {
			like($ct, qr#^application/sparql-results[+](json|xml)|text/plain#, "expected boolean result but got $ct");
		} elsif ($expected eq 'RDF') {
			like($ct, qr#^(application/(rdf-xml|n-triples))|text/((n-(triples|quads))|turtle)|application/ld[+]json#, "expected RDF result but got $ct")
		} else {
			die("Unexpected format value '$expected'");
		}
	}
	my ($expected_bool)		= $model->objects($resp, $expectedBoolean)->elements;
	if ($expected_bool) {
		my $ct	= $m->header('Content-Type');
		my $body	= $m->decoded_content;
		my $expected	= $expected_bool->value;
		if ($ct eq 'application/sparql-results+json') {
			like($body, qr#"boolean"\s*:\s*${expected}#sm, "expected boolean $expected");
		} elsif ($ct eq 'application/sparql-results+xml') {
			like($body, qr#<boolean>${expected}</boolean>#sm, "expected boolean $expected");
		} elsif ($ct =~ 'text/plain') {
			like($body, qr#${expected}#sm, "expected boolean $expected");
		} else {
			die("validate expected boolean for [$ct]: " . $expected_bool->value);
		}
	}

	my ($expected_headers)	= $model->objects($resp, $ht_headers)->elements;
	if ($expected_headers) {
		my @headers	= $model->get_list($graph, $expected_headers)->elements;
		foreach my $h (@headers) {
			my ($key)				= $model->objects($h, $ht_fieldName)->elements;
			my ($expected_value_l)	= $model->objects($h, $ht_fieldValue)->elements;
			my $expected_value		= $expected_value_l->value;
			my $actual_value		= $m->header($key->value);
			if ($expected_value =~ m<$actual_value; charset=utf-8>i) {
				pass('content-type with ignored charset=utf-8');
			} else {
				is($actual_value, $expected_value, "expected header: " . $key->value);
			}
		}
	}

	my ($expected_body)	= $model->objects($resp, $ht_body)->elements;
	if ($expected_body) {
		my $ct		= $m->header('Content-Type');
		if (not defined($ct)) {
			fail('No content-type in response');
			return;
		}
		$ct			=~ s/;.*//;
		
		warn "Body content-type: $ct\n";
		my $parser		= Attean->get_parser( media_type => $ct )->new();
		my ($chars)		= $model->objects($expected_body, $cnt_chars)->elements;
		my $actual		= $m->decoded_content;
		my $expected	= $chars->value;
		
		# fixup
		$actual		=~ s/$auth_v/$real_auth/e;
		$expected	=~ s/$auth_v/$real_auth/e;

		warn "Actual response body: " . Dumper($actual) if ($verbose);
		warn "Expected response body: " . Dumper($expected) if ($verbose);
		
		my $actual_iter		= $parser->parse_iter_from_bytes(encode_utf8($actual));
		my $expected_iter	= $parser->parse_iter_from_bytes(encode_utf8($expected));
		my $eqtest	= Attean::BindingEqualityTest->new();
		my $ok		= eval { ok( $eqtest->equals( $actual_iter, $expected_iter ), 'expected triples' ) or diag($eqtest->error) };
		unless ($ok) {
			warn Dumper({expected => $expected, actual => $actual});
		}
		if ($@) {
			diag($@);
		}
# 		fail('TODO: body');
	}

	my ($expectation)		= $model->objects($resp, $mf_expectation)->elements;
	if ($expectation) {
		fail("validate expectation: " . $expectation->value);
	}
}

sub setup_dataset {
	my $ua			= shift;
	my $endpoint	= shift;
	my $model		= shift;
	my $test		= shift;
	my $verbose		= shift;
	my (@graphs)	= $model->objects($test, $ut_graphData)->elements;
	warn scalar(@graphs) . " graphs in test dataset\n" if ($verbose);
	if (scalar(@graphs)) {
		warn "Clearing dataset ...\n" if ($verbose);
		say "REQUEST: POST $endpoint update=DROP ALL" if ($verbose);
		my $resp	= $ua->post($endpoint, {update => 'DROP ALL'});
		say "RESPONSE:\n" . $resp->as_string if ($verbose);
		die $resp->status_line unless ($resp->is_success);
		foreach my $graph (@graphs) {
			# loading contents of $uri into graph named $name
			my ($name)	= map { $_->value } $model->objects($graph, $rdfs_label)->elements;
			my ($uri)	= map { $_->value } $model->objects($graph, $ut_graph)->elements;
			warn "Loading <$uri> into graph <$name>\n" if ($verbose);
			my $resp	= $ua->get($uri);
			unless ($resp->is_success) {
				die $resp->status_line;
			}
			my $content	= $resp->decoded_content;
			my $update	= "INSERT DATA { GRAPH <$name> { $content } }";
			warn "Loading data <$name> ...\n" if ($verbose);
			my $post_resp	= $ua->post($endpoint, {update => $update});
			die $post_resp->status_line unless ($post_resp->is_success);
		}
	}
}

sub run_test {
	my $ua			= shift;
	my $endpoint	= shift;
	my $model		= shift;
	my $test		= shift;
	my $verbose		= shift;
	warn '# ' . $test->value if ($verbose);
	my ($action)	= $model->objects($test, $mf_action)->elements;
	unless ($action) {
		return fail('no action data for test');
	}
	my ($reqs)		= $model->objects($action, $requests)->elements;
	my @reqs		= $model->get_list($graph, $reqs)->elements;
	warn scalar(@reqs) . " request(s) in test\n" if ($verbose);
	my ($auth)		= $model->objects($action, $authority)->elements;
	my $auth_v		= $auth->value;
	my $uri			= new URI($endpoint);
	my $real_auth	= $uri->authority;
	
	warn "Setting up dataset...\n" if ($verbose);
	setup_dataset($ua, $endpoint, $model, $test, $verbose);
	
	my $req_number	= 0;
	foreach my $req (@reqs) {
		$req_number++;
		warn "========================================== REQUEST $req_number\n" if ($verbose);
		my $m	= make_request($endpoint, $model, $req, $auth_v, $real_auth);
# 		next unless ($m->method eq 'GET');
		warn "REQUEST:\n" . $m->as_string if ($verbose);
		my $resp	= $ua->request($m);
		warn "RESPONSE:\n" . $resp->as_string if ($verbose);
		diag(sprintf('%s %s', $m->method, $m->uri));
		validate_response($endpoint, $model, $test, $req, $resp, $auth_v, $real_auth);
		if ($verbose) {
			warn "--------------------------------- after request:\n";
			dump_dataset($endpoint);
			warn "---------------------------------\n";
		}
	}
}