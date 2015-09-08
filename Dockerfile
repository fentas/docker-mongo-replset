FROM mongo:3.0

MAINTAINER Jan Guth <jan.guth@gmail.com>

ENV SERVICE="mongo"

RUN \
  sudo apt-get update && \
  sudo apt-get install -y \
    dnsutils && \
  sudo apt-get remove -y
    perl && \
  sudo apt-get autoremove -y && \
  rm -rf /var/lib/apt/lists/* && \
  find /usr/share/doc -depth -type f ! -name copyright|xargs rm || true && \
  find /usr/share/doc -empty|xargs rmdir || true && \
  rm -rf /usr/share/man/* /usr/share/groff/* /usr/share/info/* && \
  rm -rf /usr/share/lintian/* /usr/share/linda/* /var/cache/man/*

RUN \
  wget -O /usr/bin/jq "http://stedolan.github.io/jq/download/linux64/jq" && \
  chmod +x /usr/bin/jq

COPY maintain-replset.sh /usr/local/bin/maintain-replset.sh

CMD ["/usr/local/bin/maintain-replset.sh"]
