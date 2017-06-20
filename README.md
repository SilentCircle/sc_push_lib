

# Push Notification Service Erlang Support Library #

Copyright (c) 2015,2016 Silent Circle, LLC.

__Version:__ 2.0.0

__Authors:__ Edwin Fine ([`efine@silentcircle.com`](mailto:efine@silentcircle.com)).

This application contains Erlang support modules for the Push Service.
It includes all database support.


### <a name="Database_support">Database support</a> ###

`sc_push_lib` requires at least Mnesia for local, non-replicated data, and
supports Mnesia and Postgres >= 9.4 for storage of registered push tokens.

Although `sc_push_lib` will automatically create local Mnesia database tables,
if using Postgres as a backend for push token storage, the Postgres database
and tables must be pre-created.

This is also true for running CommonTest (`make ct`).


#### <a name="Postgres">Postgres</a> ####

`sc_push_lib` uses a Postgres schema to avoid namespacing issues
and obviate the need for a separate production database for its
tables (although nothing stops you from putting the tables in a separate
database anyway).

For running CommonTest cases, it's probably best to create a totally separate
database on localhost, and an sql script is provided to assist with that.

**Hint**: After logging on as the database user, you will want to
set the search path as follows:

`SET search_path = 'scpf', 'pg_common';`

If you fail to do this, the `psql` `\d` command may display

```
No relations found.
```

<h5><a name="Production_database_setup">Production database setup</a></h5>

<h5><a name="Test_database_setup">Test database setup</a></h5>

The script to create a test Postgres database may be found in
`test/sql/sc_push_lib.sql`. It is strongly recommended that
a local Postgres installation be used for this, and the default
username and password be used as configured in `test/test.config`:

```
{connect_info,
 #{postgres => [
                {hostname, "localhost"},
                {database, "sc_push_lib_test"},
                {username, "sc_push_lib_test"},
                {password, "test"}
               ]
  }
}.
```

* Edit `/etc/postgresql/<version>/<cluster>/pg_ident.conf` and add a mapping
to your local user's login on localhost:

```
# MAPNAME           SYSTEM-USERNAME     PG-USERNAME
sc_push_lib_test    <your local user>   sc_push_lib_test
```

* Reload postgres, for example, `sudo systemctl reload postgresql`.
* Try to log in as follows:

```
$ psql -U sc_push_lib_test -d sc_push_lib_test -h localhost
Password for user sc_push_lib_test: test
...
sc_push_lib_test=#
```


* Once able to log in, you should be able to do the following:

```
sc_push_lib_test=# SET search_path = 'scpf', 'pg_common';
SET
sc_push_lib_test=# select current_database(), current_user, current_setting('search_path');
 current_database |   current_user   | current_setting
------------------+------------------+-----------------
 sc_push_lib_test | sc_push_lib_test | scpf, pg_common
(1 row)
```





## Modules ##


<table width="100%" border="0" summary="list of modules">
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/feature/add-postgresql-support/doc/sc_config.md" class="module">sc_config</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/feature/add-postgresql-support/doc/sc_push_lib.md" class="module">sc_push_lib</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/feature/add-postgresql-support/doc/sc_push_lib_app.md" class="module">sc_push_lib_app</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/feature/add-postgresql-support/doc/sc_push_lib_sup.md" class="module">sc_push_lib_sup</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/feature/add-postgresql-support/doc/sc_push_reg_api.md" class="module">sc_push_reg_api</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/feature/add-postgresql-support/doc/sc_push_reg_db_mnesia.md" class="module">sc_push_reg_db_mnesia</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/feature/add-postgresql-support/doc/sc_push_reg_db_postgres.md" class="module">sc_push_reg_db_postgres</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/feature/add-postgresql-support/doc/sc_push_req_mgr.md" class="module">sc_push_req_mgr</a></td></tr></table>

