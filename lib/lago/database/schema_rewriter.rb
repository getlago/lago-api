# frozen_string_literal: true

# Moves the objects of a PostgreSQL dump from the `public` schema to the schema
# configured with `POSTGRES_SCHEMA`.
#
# `pg_dump` qualifies every object with its schema, so `db/structure.sql` (and
# the squashed `InitialMigration`, built from it) create everything in `public`
# whatever the connection's search path is.
#
# Only the objects the dump itself creates (tables, types, sequences, functions,
# views and indexes) are moved. Objects that come from an extension, such as the
# `public.gin_trgm_ops` operator class, keep their `public` qualifier because
# the extensions stay in `public`.
#
# Statements that drop shared objects (`DROP EXTENSION`, `DROP SCHEMA`) are
# removed: they come from the `--clean` dump flag and would act on objects that
# other applications of a shared database may use.
module Lago
  module Database
    class SchemaRewriter
      DEFAULT_SCHEMA = "public"

      CREATED_OBJECT_REGEX = /
        \bCREATE\s+(?:OR\s+REPLACE\s+)?
        (?:TABLE|TYPE|SEQUENCE|FUNCTION|VIEW|MATERIALIZED\s+VIEW)\s+
        (?:IF\s+NOT\s+EXISTS\s+)?
        public\.(\w+)
      /x
      CREATED_INDEX_REGEX = /\bCREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?(\w+)\s+ON\b/
      QUALIFIED_NAME_REGEX = /\bpublic\.(\w+)/
      SEARCH_PATH_REGEX = /\bSET\s+search_path\s+TO\s+"\$user",\s*public;/
      SHARED_DROP_REGEX = /^[ \t]*DROP\s+(?:EXTENSION|SCHEMA)\s+IF\s+EXISTS\s+[^;]+;[ \t]*\n/
      CREATE_SCHEMA_REGEX = /\bCREATE\s+SCHEMA\s+(?!IF\s+NOT\s+EXISTS\b)/

      # Returns the schema new objects are created in: the first entry of the
      # search path. Returns nil when it is `public` (or blank), as nothing has
      # to be rewritten then.
      def self.target_schema(schema_search_path)
        schema = schema_search_path.to_s.split(",").first.to_s.strip.delete_prefix('"').delete_suffix('"')

        if schema.blank? || schema == DEFAULT_SCHEMA || schema.start_with?("$")
          nil
        else
          schema
        end
      end

      def initialize(sql, schema:)
        @sql = sql
        @schema = schema
      end

      def call
        created_objects = sql.scan(CREATED_OBJECT_REGEX).flatten.to_set
        created_objects.merge(sql.scan(CREATED_INDEX_REGEX).flatten)

        sql
          .gsub(QUALIFIED_NAME_REGEX) { created_objects.include?($1) ? "#{quoted_schema}.#{$1}" : $& }
          .gsub(SEARCH_PATH_REGEX, "SET search_path TO #{quoted_schema}, public;")
          .gsub(SHARED_DROP_REGEX, "")
          .gsub(CREATE_SCHEMA_REGEX, "CREATE SCHEMA IF NOT EXISTS ")
      end

      private

      attr_reader :sql, :schema

      def quoted_schema
        @quoted_schema ||= PG::Connection.quote_ident(schema)
      end
    end
  end
end
