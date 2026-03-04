#!/bin/sh
npx @marp-team/marp-cli slide-deck.md -o slide-deck.html --html --no-stdin && open slide-deck.html
