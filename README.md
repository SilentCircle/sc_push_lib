

# Push Notification Service Erlang Support Library #

Copyright (c) 2015,2016 Silent Circle, LLC.

__Version:__ 2.0.1

__Authors:__ Edwin Fine ([`efine@silentcircle.com`](mailto:efine@silentcircle.com)).

This application contains Erlang support modules for the Push Service.
It includes all database support.


### <a name="Database_support">Database support</a> ###

`sc_push_lib` requires at least Mnesia for local, non-replicated
data, and supports Mnesia and Postgres >= 9.4 for storage of
registered push tokens.

Although `sc_push_lib` will automatically create local Mnesia
database tables, if using Postgres as a backend for push token
storage, the Postgres database and tables must be pre-created.

This is also true for running CommonTest (`make ct`).


#### <a name="Database_Selection">Database Selection</a> ####

As already mentioned, Mnesia is always used for local data, but you
can choose between Mnesia and Postgres for push token storage.

To select the database you want to use for push token storage,
change the `db_mod` tuple in the `sc_push_lib` part of `sys.config`
to the name of one of the available database backend modules. See
the sample `config/shell.config` for exact syntax.

<h5><a name="Currently_available_modules">Currently available modules</a></h5>



<dt><code>sc_push_reg_db_mnesia</code></dt>



<dd>Mnesia push token backend</dd>




<dt><code>sc_push_reg_db_postgres</code></dt>



<dd>Postgres push token backend</dd>



You will need to restart scpf to make this change active.

```
%% ...
{sc_push_lib,
 [
  {db_pools,
   [
    {sc_push_reg_pool,
    [ % sizeargs
      % ...
    ],
    [ % workerargs
      {db_mod, sc_push_reg_db_postgres},
      % ...
    ]}]}]
}
%% ...
```


#### <a name="Postgres_Configuration">Postgres Configuration</a> ####

`sc_push_lib` uses the default `public` Postgres schema for maximum
compatibility.  However, this can be overridden in the `sys.config`,
as can the push token table name, for flexibility. Using a different
schema name helps to avoid namespacing issues, and obviates the need
for a separate production database for its tables (although nothing
stops you from putting the tables in a separate database anyway).

For running CommonTest cases, it is probably wise to create a
totally separate database on localhost, and an sql script is
provided to assist with that.

**Hint**: When testing, after logging on as the database user, you
may want to set the search path as follows:<code>
SET search_path = &#39;scpf&#39;,&#39;pg_common&#39;;
</code>

If you fail to do this, the `psql` `\d` command may display
`No relations found.`

<h5><a name="Production_database_setup">Production database setup</a></h5>

Modify the test script to suit your environment and create the
scpf table(s) accordingly.

Modify the `sys.config` to match your environment, by adding
a section similar to that shown in the example below.

The settings for `table_config` key as shown are the defaults, so
the entire key could be omitted. Leaving it in does make it more
obvious where things are found, though.

```
 %% ...
 {sc_push_lib,
  [
   {db_pools,
    [
     {sc_push_reg_pool, % name
      [ % sizeargs
       {size, 50},
       {max_overflow, 0}
      ],
      [ % workerargs
       {db_mod, sc_push_reg_db_postgres},
       {db_config, #{connection => [
                                    {hostname, "localhost"},
                                    {database, "sc_push_lib_test"},
                                    {username, "sc_push_lib_test"},
                                    {password, "test"}
                                   ],
                     table_config => [
                                      {table_schema, "public"},
                                      {table_name, "push_tokens"}
                                     ]
                    }}
      ]}
    ]}
  ]}
  %% ...
```

<h5><a name="Test_database_setup">Test database setup</a></h5>

The script to create a test Postgres database may be found in
`test/sql/sc_push_lib.sql`. It is strongly recommended that
a local Postgres installation be used for this, and the default
username and password be used as configured in `test/test.config`:

```
{connect_info,
 #{postgres => #{connection => [
                                {hostname, "localhost"},
                                {database, "sc_push_lib_test"},
                                {username, "sc_push_lib_test"},
                                {password, "test"}
                               ],
                 table_config => [
                                  {table_schema, "scpf"},
                                  {table_name, "push_tokens"}
                                 ]
                }
  }
}.
```

* Edit `/etc/postgresql/<version>/<cluster>/pg_ident.conf` and add
a mapping to your local user's login on localhost:

```
# MAPNAME           SYSTEM-USERNAME     PG-USERNAME
sc_push_lib_test    <your local user>   sc_push_lib_test
```

* Reload postgres, for example, `sudo systemctl reload
postgresql`.
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
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/master/doc/sc_config.md" class="module">sc_config</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/master/doc/sc_push_lib.md" class="module">sc_push_lib</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/master/doc/sc_push_lib_app.md" class="module">sc_push_lib_app</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/master/doc/sc_push_lib_sup.md" class="module">sc_push_lib_sup</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/master/doc/sc_push_reg_api.md" class="module">sc_push_reg_api</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/master/doc/sc_push_reg_db.md" class="module">sc_push_reg_db</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/master/doc/sc_push_reg_db_mnesia.md" class="module">sc_push_reg_db_mnesia</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/master/doc/sc_push_reg_db_postgres.md" class="module">sc_push_reg_db_postgres</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/master/doc/sc_push_req_mgr.md" class="module">sc_push_req_mgr</a></td></tr></table>

