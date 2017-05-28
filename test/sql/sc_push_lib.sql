DROP USER IF EXISTS sc_push_lib_test;
CREATE USER sc_push_lib_test
    WITH SUPERUSER CREATEDB CREATEROLE REPLICATION
    PASSWORD 'test';

DROP DATABASE IF EXISTS sc_push_lib_test;
CREATE DATABASE sc_push_lib_test WITH OWNER sc_push_lib_test;

\connect sc_push_lib_test

--
-- Create schema
--

CREATE SCHEMA IF NOT EXISTS scpf AUTHORIZATION sc_push_lib_test;

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
  created_on TIMESTAMP WITHOUT TIME ZONE DEFAULT (now() at time zone 'utc'),
  last_seen_on TIMESTAMP WITHOUT TIME ZONE DEFAULT (now() at time zone 'utc'),
  last_invalid_on TIMESTAMP WITHOUT TIME ZONE,
  last_xscdevid VARCHAR(64) NOT NULL
);
CREATE INDEX ON scpf.push_tokens (uuid);
CREATE INDEX ON scpf.push_tokens (type,token);
CREATE INDEX ON scpf.push_tokens (last_xscdevid,uuid);
CREATE UNIQUE INDEX push_tokens_match_idx ON scpf.push_tokens (uuid,type,token,appname);

