

# Push Notification Service Erlang Support Library #

Copyright (c) 2015 Silent Circle, LLC.

__Version:__ 1.1.4

__Authors:__ Edwin Fine ([`efine@silentcircle.com`](mailto:efine@silentcircle.com)).

This application contains Erlang support modules for the Push Service.


#### <a name="Testing">Testing</a> ####

Testing is done with Common Test. The tests depend on libraries not needed for
production, so there is some special code in `rebar.config.script` to support
getting and building the extra dependencies without including them in the
production builds.

`ct_deps.config` is a supplementary rebar-format config file containing the
extra dependencies, which is dynamically merged with the active rebar config
file, depending on the environment variable `REBAR_EXTRA_DEPS_CFG`.

`REBAR_EXTRA_DEPS_CFG` must either be undefined or the empty string, or be set
to `ct_deps.config`.

See rebar.config.script for usage and behavior. Also see
`extra_tests/rebar_config_SUITE.erl`.


## Modules ##


<table width="100%" border="0" summary="list of modules">
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/master/doc/sc_config.md" class="module">sc_config</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/master/doc/sc_push_lib.md" class="module">sc_push_lib</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/master/doc/sc_push_lib_app.md" class="module">sc_push_lib_app</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/master/doc/sc_push_lib_sup.md" class="module">sc_push_lib_sup</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/master/doc/sc_push_reg_api.md" class="module">sc_push_reg_api</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/master/doc/sc_push_reg_db.md" class="module">sc_push_reg_db</a></td></tr>
<tr><td><a href="http://github.com/SilentCircle/sc_push_lib/blob/master/doc/sc_push_req_mgr.md" class="module">sc_push_req_mgr</a></td></tr></table>

