#!/bin/bash

git add .
git commit -m "post $(date +'%Y-%m-%d %H:%M:%S')"
git push origin gh-pages

