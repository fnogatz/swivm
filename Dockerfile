FROM ubuntu:16.04

ARG version=7.7.15
ARG user=prolog

ENV DEBIAN_FRONTEND noninteractive
ENV JAVA_HOME       /usr/lib/jvm/java-8-oracle

RUN apt-get update && \
  apt-get install -y --no-install-recommends locales && \
  locale-gen en_US.UTF-8 && \
  apt-get dist-upgrade -y && \
  apt-get --purge remove openjdk* && \
  echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections && \
  echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu xenial main" > /etc/apt/sources.list.d/webupd8team-java-trusty.list && \
  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys EEA14886 && \
  apt-get update && \
  apt-get install -y --no-install-recommends oracle-java8-installer oracle-java8-set-default && \
  apt-get clean all
RUN apt-get install -y autoconf make libgmp-dev libxt-dev libjpeg-dev libxpm-dev libxft-dev libdb-dev libssl-dev unixodbc-dev libarchive-dev git curl

RUN useradd -ms /bin/bash ${user}
USER $user
RUN git clone https://github.com/fnogatz/swivm.git ~/.swivm
RUN cd ~/.swivm && git checkout `git describe --abbrev=0 --tags`
RUN cd ~/.swivm && export SWIVM_DIR="~/.swivm" && \ 
	. ~/.swivm/swivm.sh && \
		(swivm install ${version} || \ 
			(cp -r ~/.swivm/src/swipl-devel-${version} ~/.swivm/src/swipl-${version} && \ 
			swivm install ${version}))
RUN ln -sf ~/.swivm/versions/${version}/bin/swipl ~/swipl
ENTRYPOINT ["/bin/bash", "-c", "~/swipl"]