

# Module sc_push_lib #
* [Description](#description)
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

Push service common library functions.

Copyright (c) 2015 Silent Circle

__Authors:__ Edwin Fine ([`efine@silentcircle.com`](mailto:efine@silentcircle.com)).

<a name="types"></a>

## Data Types ##




### <a name="type-std_proplist">std_proplist()</a> ###


<pre><code>
std_proplist() = <a href="sc_types.md#type-proplist">sc_types:proplist</a>(atom(), term())
</code></pre>

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#get_service_config-1">get_service_config/1</a></td><td>Get service configuration.</td></tr><tr><td valign="top"><a href="#register_service-1">register_service/1</a></td><td>Register a service in the service configuration registry.</td></tr><tr><td valign="top"><a href="#unregister_service-1">unregister_service/1</a></td><td>Unregister a service in the service configuration registry.</td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="get_service_config-1"></a>

### get_service_config/1 ###

<pre><code>
get_service_config(Service::term()) -&gt; {ok, <a href="#type-std_proplist">std_proplist()</a>} | {error, term()}
</code></pre>
<br />

Get service configuration

__See also:__ [start_service/1](#start_service-1).

<a name="register_service-1"></a>

### register_service/1 ###

<pre><code>
register_service(Svc) -&gt; ok
</code></pre>

<ul class="definitions"><li><code>Svc = <a href="sc_types.md#type-proplist">sc_types:proplist</a>(atom(), term())</code></li></ul>

Register a service in the service configuration registry.
Requires a property `{name, ServiceName :: atom()}` to be present
in `Svc`.

__See also:__ [start_service/1](#start_service-1).

<a name="unregister_service-1"></a>

### unregister_service/1 ###

<pre><code>
unregister_service(ServiceName::atom()) -&gt; ok
</code></pre>
<br />

Unregister a service in the service configuration registry.

__See also:__ [start_service/1](#start_service-1).

