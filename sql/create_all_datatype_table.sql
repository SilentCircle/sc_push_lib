--
-- Create                       a table that has an example of every supported data type
-- for                       development and testing
--
CREATE                       SCHEMA IF NOT EXISTS test AUTHORIZATION scadmin;

--
-- Set                       up test schema
--
SET                       search_path = test, pg_catalog;

DROP TABLE IF EXISTS test.all_data_types;
CREATE TABLE IF NOT EXISTS test.all_data_types (
    id                    serial,
    null_field            character varying,
    c_bigint              bigint                           NOT NULL DEFAULT 100,
    c_bigserial           bigserial,
    c_bit                 bit(32)                          NOT NULL DEFAULT B'11110000111100001111000011110000',
    c_bit_varying         bit varying(32)                  NOT NULL DEFAULT B'11111111',
    c_boolean_true        boolean                          NOT NULL DEFAULT 'true',
    c_boolean_false       boolean                          NOT NULL DEFAULT 'false',
    c_box                 box                              NOT NULL DEFAULT '((0, 0), (1, 1))',
    c_bytea               bytea                            NOT NULL DEFAULT E'\\xCAFEBABE',
    c_character           character(32)                    NOT NULL DEFAULT 'character32',
    c_character_varying   character varying(32)            NOT NULL DEFAULT 'character_varying32',
    c_cidr                cidr                             NOT NULL DEFAULT '192.168.100.128/25',
    c_circle              circle                           NOT NULL DEFAULT '<(0, 0), 1>',
    c_date                date                             NOT NULL DEFAULT '2017-06-07',
    c_double_precision    double precision                 NOT NULL DEFAULT 3.1415926535897932384626433,
    c_inet                inet                             NOT NULL DEFAULT '192.168.1.1',
    c_integer             integer                          NOT NULL DEFAULT 102,
    c_integer_array2d     integer[][]                      NOT NULL DEFAULT '{{1,2,3}, {4,5,6}, {7,8,9}}',
    c_interval            interval(6)                      NOT NULL DEFAULT INTERVAL '10 YEARS 9 MONTHS 8 DAYS 7 MINUTES 6.123456 SECONDS',
    c_interval_y          interval YEAR                    NOT NULL DEFAULT INTERVAL '9 YEARS',
    c_interval_m          interval MONTH                   NOT NULL DEFAULT INTERVAL '8 MONTHS',
    c_interval_d          interval DAY                     NOT NULL DEFAULT INTERVAL '7 DAYS',
    c_interval_h          interval HOUR                    NOT NULL DEFAULT INTERVAL '6 HOURS',
    c_interval_min        interval MINUTE                  NOT NULL DEFAULT INTERVAL '5 MINUTES',
    c_interval_s          interval SECOND(6)               NOT NULL DEFAULT INTERVAL '4.123456 SECONDS',
    c_interval_y2m        interval YEAR TO MONTH           NOT NULL DEFAULT INTERVAL '10 YEARS 9 MONTHS',
    c_interval_d2h        interval DAY TO HOUR             NOT NULL DEFAULT INTERVAL '7 DAYS 6 HOURS',
    c_interval_d2m        interval DAY TO MINUTE           NOT NULL DEFAULT INTERVAL '7 DAYS 6 HOURS 5 MINUTES',
    c_interval_d2s        interval DAY TO SECOND(6)        NOT NULL DEFAULT INTERVAL '7 DAYS 6 HOURS 5 MINUTES 4.234567 SECONDS',
    c_interval_h2m        interval HOUR TO MINUTE          NOT NULL DEFAULT INTERVAL '10 HOURS 59 MINUTES',
    c_interval_h2s        interval HOUR TO SECOND(6)       NOT NULL DEFAULT INTERVAL '10 HOURS 59 MINUTES 2.345678 SECONDS',
    c_interval_m2s        interval MINUTE TO SECOND(6)     NOT NULL DEFAULT INTERVAL '10 MINUTES 15.123456 SECONDS',
    c_json                json                             NOT NULL DEFAULT '{"product": "PostgreSQL", "version": 9.4, "jsonb":false, "a":[1,2,3]}',
    c_jsonb               jsonb                            NOT NULL DEFAULT '{"product": "PostgreSQL", "version": 9.4, "jsonb":true,  "a":[1,2,3]}',
    c_line                line                             NOT NULL DEFAULT '((0, 0), (1, 1))',
    c_lseg                lseg                             NOT NULL DEFAULT '((0, 0), (0, 1))',
    c_macaddr             macaddr                          NOT NULL DEFAULT '08:00:2b:01:02:03',
    c_money               money                            NOT NULL DEFAULT '$1,234,567.89',
    c_numeric             numeric(21, 10)                  NOT NULL DEFAULT '1234567890.0123456789',
    c_path                path                             NOT NULL DEFAULT '((0, 1), (1, 2), (2, 3))',
    c_pg_lsn              pg_lsn                           NOT NULL DEFAULT 'ABCD/CDEF',
    c_point               point                            NOT NULL DEFAULT '(10, 10)',
    c_polygon             polygon                          NOT NULL DEFAULT '((0, 0), (0, 1), (1, 1), (1, 0))', -- box
    c_real                real                             NOT NULL DEFAULT 2.71828,
    c_smallint            smallint                         NOT NULL DEFAULT 42,
    c_smallserial         smallserial,
    c_text                text                             NOT NULL DEFAULT 'No man is an iland, entire of itself;',
    c_time                time(6)                          NOT NULL DEFAULT '04:05:06.345678',
    c_timestamp           timestamp(6) without time zone   NOT NULL DEFAULT TIMESTAMP WITHOUT TIME ZONE '2017-06-05 04:05:06.789',
    c_timestamp_tz        timestamp(6) with time zone      NOT NULL DEFAULT TIMESTAMP WITH TIME ZONE '2017-06-05 04:05:06.789 America/New_York',
    c_tsquery             tsquery                          NOT NULL DEFAULT 'fat & (rat | cat)'::tsquery,
    c_tsvector            tsvector                         NOT NULL DEFAULT 'a fat cat sat on a mat and ate a fat rat'::tsvector,
    c_txid_snapshot       txid_snapshot,
    c_uuid                uuid                             NOT NULL DEFAULT '1a54f33b-f891-45f6-bf8d-5e6fd36af617',
    c_xml                 xml                              NOT NULL DEFAULT XML '<html><head/><body/></html>'
);
