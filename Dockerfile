FROM ruby:3.0.3


# throw errors if Gemfile has been modified since Gemfile.lock
RUN bundle config --global frozen 1

WORKDIR /usr/src/app

COPY Gemfile Gemfile.lock ./


COPY . .
RUN ls -l
RUN bundle install

CMD ["bundle", "exec", "ruby", "main.rb"]