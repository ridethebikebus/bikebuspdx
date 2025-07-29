FROM ruby:3.2.3

RUN apt-get update && apt-get install -y webp && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY .ruby-gemset .
COPY .ruby-version .
COPY Gemfile .
RUN bundle install

WORKDIR /app

EXPOSE 22030
ENTRYPOINT ["jekyll"]
CMD ["serve", "--port", "22030", "--host", "0.0.0.0", "--watch", "--livereload", "--drafts", "--future"]
