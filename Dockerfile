FROM ruby:2.7.1

MAINTAINER Jay Luker <jay_luker@harvard.edu>

ARG REVISION=master
ENV RAILS_ENV development
ENV GEM_HOME /opt/canvas/.gems
ENV YARN_VERSION 0.27.5-1

# add nodejs and recommended ruby repos
RUN apt-get update \
    && apt-get -y install curl software-properties-common \
    && apt-get update \
    && apt-get install -y supervisor redis-server \
        zlib1g-dev libxml2-dev libxslt1-dev libsqlite3-dev postgresql \
        postgresql-contrib libpq-dev libxmlsec1-dev curl make g++ git \
        unzip fontforge libicu-dev


# install nodejs
ENV NODE_VERSION=12.6.0
RUN apt install -y curl
RUN curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.34.0/install.sh | bash
ENV NVM_DIR=/root/.nvm
RUN . "$NVM_DIR/nvm.sh" && nvm install ${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && nvm use v${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && nvm alias default v${NODE_VERSION}
ENV PATH="/root/.nvm/versions/node/v${NODE_VERSION}/bin/:${PATH}"
RUN node --version
RUN npm --version

# install yarn
RUN npm install -g yarn
RUN yarn -v

RUN apt-get install -y --no-install-recommends unzip fontforge

RUN apt-get clean && rm -Rf /var/cache/apt

# Set the locale to avoid active_model_serializers bundler install failure
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

RUN groupadd -r canvasuser -g 433 && \
    adduser --uid 431 --system --gid 433 --home /opt/canvas canvasuser && \
    adduser canvasuser sudo && \
    echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

RUN if [ -e /var/lib/gems/$RUBY_MAJOR.0/gems/bundler-* ]; then BUNDLER_INSTALL="-i /var/lib/gems/$RUBY_MAJOR.0"; fi
#RUN gem uninstall --all --ignore-dependencies --force $BUNDLER_INSTALL bundler
RUN  gem install bundler --no-document -v 1.15.2
RUN chown -R canvasuser: $GEM_HOME

#RUN gem install bundler --version 1.14.6

COPY assets/dbinit.sh /opt/canvas/dbinit.sh
COPY assets/start.sh /opt/canvas/start.sh
RUN chmod 755 /opt/canvas/*.sh

COPY assets/supervisord.conf /etc/supervisor/supervisord.conf
COPY assets/pg_hba.conf /etc/postgresql/9.3/main/pg_hba.conf
RUN ls -la /etc/postgresql/9.3/main
# RUN sed -i "/^#listen_addresses/i listen_addresses='*'" /etc/postgresql/9.3/main/postgresql.conf

RUN cd /opt/canvas \
    && git clone https://github.com/instructure/canvas-lms.git \
    && cd canvas-lms \
    && git checkout $REVISION

WORKDIR /opt/canvas/canvas-lms

COPY assets/database.yml config/database.yml
COPY assets/redis.yml config/redis.yml
COPY assets/cache_store.yml config/cache_store.yml
COPY assets/development-local.rb config/environments/development-local.rb
COPY assets/outgoing_mail.yml config/outgoing_mail.yml

RUN for config in amazon_s3 delayed_jobs domain file_store security external_migration \
       ; do cp config/$config.yml.example config/$config.yml \
       ; done
RUN gem install bundler --version 2.2.17

ENV PULSAR_VERSION=2.6.1
ENV PULSAR_CLIENT_SHA512=90fdb6e3ad85c9204f2b20a9077684f667f84be32df0952f8823ccee501c9d64a4c8131cab38a295a4cb66e2b63211afcc24f32130ded47e9da8f334ec6053f5
ENV PULSAR_CLIENT_DEV_SHA512=d0cc58c0032cb35d4325769ab35018b5ed823bc9294d75edfb56e62a96861be4194d6546107af0d5f541a778cdc26274aac9cb7b5ced110521467f89696b2209

RUN cd "$(mktemp -d)" && \
    curl -SLO 'http://archive.apache.org/dist/pulsar/pulsar-'$PULSAR_VERSION'/DEB/apache-pulsar-client.deb' && \
    curl -SLO 'http://archive.apache.org/dist/pulsar/pulsar-'$PULSAR_VERSION'/DEB/apache-pulsar-client-dev.deb' && \
    echo $PULSAR_CLIENT_SHA512 '*apache-pulsar-client.deb' | shasum -a 512 -c -s - && \
    echo $PULSAR_CLIENT_DEV_SHA512 '*apache-pulsar-client-dev.deb' | shasum -a 512 -c -s - && \
    apt install ./apache-pulsar-client*.deb && \
    rm ./apache-pulsar-client*.deb && \
    rm /usr/lib/libpulsarnossl.so* && \
    rm /usr/lib/libpulsar.a && \
    rm /usr/lib/libpulsarwithdeps.a

# RUN gem install pulsar-client -v '2.6.1.pre.beta.2'
RUN $GEM_HOME/bin/bundle install --jobs 8 --without="mysql"
# RUN . "$NVM_DIR/nvm.sh"  && nvm uninstall v12.6.0
RUN . "$NVM_DIR/nvm.sh" && nvm install 14
RUN . "$NVM_DIR/nvm.sh" && nvm use v14
RUN . "$NVM_DIR/nvm.sh" && nvm alias default v14
RUN ls -la /root/.nvm/versions/node/
ENV PATH="/root/.nvm/versions/node/v14.18.1/bin/:${PATH}"
RUN node -v
RUN yarn install --pure-lockfile
RUN COMPILE_ASSETS_NPM_INSTALL=0 $GEM_HOME/bin/bundle exec rake canvas:compile_assets_dev

RUN mkdir -p log tmp/pids public/assets public/stylesheets/compiled \
    && touch Gemmfile.lock

RUN service postgresql start && /opt/canvas/dbinit.sh

RUN chown -R canvasuser: /opt/canvas
RUN chown -R canvasuser: /tmp/attachment_fu/

# postgres
EXPOSE 5432
# redis
EXPOSE 6379
# canvas
EXPOSE 3000

CMD ["/opt/canvas/start.sh"]
