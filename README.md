# Bike Bus PDX

Run `make serve` to run the site through Docker.
This means you need Docker, but you don't need to worry about Ruby.

Open a browser to <http://localhost:22030> (you can remember the port because of the 2030 Bike Plan).

Otherwise, this is a pretty normal Jekyll site- new blog posts in `_posts`, etc.

## Bike Bus Mini-Sites

There is a `_data/buses.yml` file which contains the data that drives bike bus mini-sites
and the 'find your bike bus' list.

Check out that file to see the supported fields.

Each bus gets a site at `/<slug>`. So the Alameda Bike Bus site is at `/alameda`.

The code for this is in `_plugins/bus_site_generator.rb`.

## Optimize Images

Run `make optimize-images` to build webp files for every file in `assets/images`.
This is done through the container so does not require any local executables.

## Original Theme

This site originally used the Aditu theme. It's been customized heavily but referring to the original
can be helpful.

Its docs are in the `aditu-jekyll-theme-v1.2` folder.

Check out a [demo](https://aditu.netlify.com/).
