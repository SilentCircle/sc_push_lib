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

SET search_path = scpf, pg_catalog;
