---
title: Dump SQL DB from a container
date: 2020-09-14 13:24:05
author: Patrick Kerwood
excerpt: This is just two simple commands to backup and restore an active MySQL/MariaDB database running in a container.
type: post
blog: true
tags: [docker, sql]
---
{{ $frontmatter.excerpt }}

So basically, below command just a `mysqldump` command, but it saves the dump file on the host instead of in the container. I use these commands maybe more often than I'd like to admit, when backing up a private hosted SQL database.

Again, I post these two commands because og my own deteriorating memory.

### Backup
```sh
docker exec -i [mysql_container_name] mysqldump -u root -p[root_password] [database_name] > dumpfilename.sql
```

### Restore
```sh
docker exec -i [mysql_container_name] mysql -u root -p[root_password] [database_name] < dumpfilename.sql
```
---