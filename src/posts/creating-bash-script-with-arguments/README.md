---
title: Creating a bash script with commandline arguments
date: 2024-05-5 23:13:06
author: Patrick Kerwood
excerpt: When creating a good bash script for others to use, it's important to create a good user experience. Creating good usage arguments makes all the differnce and really makes your script look proffesional instead of just a list of commands bunced together in a file.
blog: true
tags: [bash]
meta:
- name: description
  content: How to create a bash script with commandline arguments.
---

{{ $frontmatter.excerpt }}

Since there isn't a good framework for this in Bash, like in other programming
languages, you will have to figure something out yourself. I did a lot of
searching around and found below code to be the way that suits my needs best.

I have created a very simple dummy script that demonstrates how it works. The
script will exit with a given exit code at a specified interval.

```sh
#!/usr/bin/env bash
set -e

usage() {
 echo "Usage: $0 [OPTIONS]"
 echo "Options:"
 echo " -h, --help           Display this help message"
 echo " -s, --sleep-seconds  Seconds to sleep before exiting, DEFAULT: 60"
 echo " -e, --exit-code      Exit code to exit with, REQUIRED"
}

# Setting default values.
SLEEP=60

while [ $# -gt 0 ] ; do
  case $1 in
    -s | --sleep-seconds) SLEEP="$2"; shift 2 ;;
    -e | --exit-code) EXIT="$2"; shift 2 ;;
    -h | --help) usage; exit 1 ;;
    *)
      echo "Invalid option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# Checking required parameters.
if [ -z "$EXIT" ]; then
  echo -e "\nThe argument --exit-code is requried.\n"
  usage
  exit 1
fi

echo "Sleeping for $SLEEP seconds.. ZzzZzzZ"
sleep "$SLEEP"
echo "Exiting with code: $EXIT"
exit "$EXIT"
```
