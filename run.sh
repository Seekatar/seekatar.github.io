#! /bin/sh
cd /srv/jekyll
bundler exec jekyll serve --host 0.0.0.0 --force_polling --livereload
