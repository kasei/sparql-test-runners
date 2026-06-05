FROM perl:5.42.2

WORKDIR /usr/src/attean

RUN apt-get update; \
    apt-get install -y liblmdb-dev \
    ; \
    apt-get dist-clean

ARG NO_NETWORK_TESTING=1
RUN cpanm --notest Attean
RUN git clone https://github.com/w3c/rdf-tests.git
COPY *.pl ./
ENTRYPOINT ["/usr/local/bin/perl"]

# Build:
#
#  % docker build -t sparql-test .
#
# and run with:
#
### SPARQL Protocol
#
#  % docker run -it --rm sparql-test prot.pl --manifest rdf-tests/sparql/sparql11/protocol/manifest.ttl http://ENDPOINT/sparql
#
### SPARQL Graph Store Protocol
#
#  % docker run -it --rm sparql-test gsp.pl --manifest rdf-tests/sparql/sparql11/graph-store-protocol/manifest.ttl http://ENDPOINT/sparql http://ENDPOINT/gsp
#
# or with some features disabled:
#
#  % docker run -it --rm sparql-test gsp.pl --no-direct --manifest rdf-tests/sparql/sparql11/graph-store-protocol/manifest.ttl http://ENDPOINT/sparql http://ENDPOINT/gsp
#  % docker run -it --rm sparql-test gsp.pl --no-indirect --manifest rdf-tests/sparql/sparql11/graph-store-protocol/manifest.ttl http://ENDPOINT/sparql http://ENDPOINT/gsp
#  % docker run -it --rm sparql-test gsp.pl --no-creation --manifest rdf-tests/sparql/sparql11/graph-store-protocol/manifest.ttl http://ENDPOINT/sparql http://ENDPOINT/gsp
#
