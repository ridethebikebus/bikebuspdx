FROM ruby:3.2.3

WORKDIR /build
COPY .ruby-gemset .
COPY .ruby-version .
COPY Gemfile .
COPY Gemfile.lock .
RUN bundle install

WORKDIR /app

EXPOSE 22030
ENTRYPOINT ["jekyll"]
CMD ["serve", "--port", "22030", "--host", "0.0.0.0", "--watch", "--livereload", "--drafts", "--future"]
