FROM dockerfile/mongodb

MAINTAINER Andrew Zenk <andrew@andrewzenk.com>

RUN wget -O /usr/bin/jq "http://stedolan.github.io/jq/download/linux64/jq"
RUN chmod +x /usr/bin/jq

COPY maintain-replset.sh /usr/local/bin/maintain-replset.sh

CMD ["/usr/local/bin/maintain-replset.sh"]
