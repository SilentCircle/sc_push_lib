\connect scsrsdata

--
-- Create schemas
--

CREATE SCHEMA IF NOT EXISTS scpf AUTHORIZATION postgres;

--
-- Set up scpf schema
--
SET search_path = scpf, pg_catalog;

--
-- Table: scpf.push_tokens
--
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
CREATE UNIQUE INDEX push_tokens_match_idx ON scpf.push_tokens (uuid,type,token,appname);

