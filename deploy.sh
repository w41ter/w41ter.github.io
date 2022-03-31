#!/bin/bash

dir=$(pwd)
bundle exec jekyll build -d ${dir}_site
pushd ${dir}_site/ >/dev/null

git add .
git commit -m "post $(date +'%Y-%m-%d %H:%M:%S')"
git push origin gh-pages

popd >/dev/null

