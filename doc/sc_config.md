

# Module sc_config #
* [Description](#description)
* [Function Index](#index)
* [Function Details](#functions)

Configuration server for sc_push.

__Behaviours:__ [`gen_server`](gen_server.md).

__Authors:__ Edwin Fine.

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#delete-1">delete/1</a></td><td>Delete key.</td></tr><tr><td valign="top"><a href="#get-1">get/1</a></td><td>Get value for key, or undefined is not found.</td></tr><tr><td valign="top"><a href="#get-2">get/2</a></td><td>Get value for key, or default value if key not found.</td></tr><tr><td valign="top"><a href="#set-2">set/2</a></td><td>Set key/value pair.</td></tr><tr><td valign="top"><a href="#start_link-0">start_link/0</a></td><td>
Starts the server.</td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="delete-1"></a>

### delete/1 ###

<pre><code>
delete(K::term()) -&gt; ok
</code></pre>
<br />

Delete key.

<a name="get-1"></a>

### get/1 ###

<pre><code>
get(K::term()) -&gt; term() | undefined
</code></pre>
<br />

Get value for key, or undefined is not found.

<a name="get-2"></a>

### get/2 ###

<pre><code>
get(K::term(), Def::term()) -&gt; term()
</code></pre>
<br />

Get value for key, or default value if key not found.

<a name="set-2"></a>

### set/2 ###

<pre><code>
set(K::term(), V::term()) -&gt; ok
</code></pre>
<br />

Set key/value pair.

<a name="start_link-0"></a>

### start_link/0 ###

<pre><code>
start_link() -&gt; {ok, pid()} | ignore | {error, term()}
</code></pre>
<br />

Starts the server

