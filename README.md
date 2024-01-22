# bikebuspdx.org

The docs use the [Minimal Mistakes](https://github.com/mmistakes/minimal-mistakes) theme.
Check it out for usage.

Also refer to the [Jekyll Docs](https://jekyllrb.com/docs/pages/)
for information about how to structure content, what goes into frontmatter, etc.

## Local development

Run `make run-local` to build and run a docker container to serve the Jekyll site locally
(this avoids you having to deal with Ruby).
You will need to restart it in certain cases, like modifying the config file,
but the build will watch for changes and you'll see them when you reload your browser.

## Deployment

Deployment is handled via Github Actions and deploys to Github Pages.

View the site at <https://bikebuspdx.org>.
