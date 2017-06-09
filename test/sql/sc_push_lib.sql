DROP USER IF EXISTS scadmin;
CREATE USER scadmin
    WITH SUPERUSER CREATEDB CREATEROLE REPLICATION
    PASSWORD 'changeme';

CREATE DATABASE silentcircle WITH OWNER scadmin;

\connect silentcircle

--
-- Create schemas
--

CREATE SCHEMA IF NOT EXISTS kamailio AUTHORIZATION scadmin;
CREATE SCHEMA IF NOT EXISTS scaccounts AUTHORIZATION scadmin;
CREATE SCHEMA IF NOT EXISTS scaccountstest AUTHORIZATION scadmin;
CREATE SCHEMA IF NOT EXISTS scpf AUTHORIZATION scadmin;
CREATE SCHEMA IF NOT EXISTS scsrsdata AUTHORIZATION scadmin;
CREATE SCHEMA IF NOT EXISTS sentry AUTHORIZATION scadmin;

--
-- Set up scpf schema
--
SET search_path = scpf, pg_catalog;

--
-- Table: scpf.push_tokens
--
DROP TABLE IF EXISTS scpf.push_tokens;
CREATE TABLE IF NOT EXISTS scpf.push_tokens (
  id SERIAL NOT NULL,
  uuid VARCHAR(64) NOT NULL,
  type VARCHAR(10) NOT NULL,
  token VARCHAR(512) DEFAULT 'text/plain',
  appname VARCHAR(64) NOT NULL,
  created_on TIMESTAMP WITHOUT TIME ZONE DEFAULT now(),
  last_seen_on TIMESTAMP WITHOUT TIME ZONE DEFAULT now(),
  last_invalid_on TIMESTAMP WITHOUT TIME ZONE,
  last_xscdevid VARCHAR(64) NOT NULL
);
CREATE INDEX ON scpf.push_tokens (uuid);
CREATE UNIQUE INDEX push_tokens_match_idx ON scpf.push_tokens (uuid,type,token,appname);

drop function if exists scpf.push_tokens_upsert(text,text,text,text,text);
create or replace function scpf.push_tokens_upsert
    (uuid_ text, type_ text, token_ text, appname_ text, xscdevid_ text)
    returns integer as $$
  declare
    r record;
  begin
    select a.id,
           (a.last_seen_on < now() - interval '1 day') or
             (a.last_invalid_on is not null
                and a.last_seen_on < a.last_invalid_on) as needs_atime,
           a.last_xscdevid is null or a.last_xscdevid <> xscdevid_ as needs_xscdevid
        into r
      from scpf.push_tokens a
      where a.uuid = uuid_
        and a.type = type_
        and a.token = token_
        and a.appname = appname_
      limit 1;
    if not found then
      insert into scpf.push_tokens (uuid,type,token,appname,last_xscdevid)
        values (uuid_,type_,token_,appname_,xscdevid_);
      return 1;
    else
      if r.needs_atime or r.needs_xscdevid then
        update scpf.push_tokens
          set last_seen_on = now()
          where id = r.id;

        if r.needs_xscdevid then
          update scpf.push_tokens
            set last_xscdevid = xscdevid_
            where id = r.id;
          return 3;
        end if;
        return 2;
      end if;
    end if;
    return 0;
  end;
  $$ language plpgsql volatile strict;

--
-- Set up other schemas
--
-- BLAH BLAH
SET search_path = scpf, pg_catalog;
