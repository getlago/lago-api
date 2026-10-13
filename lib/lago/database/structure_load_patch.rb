# frozen_string_literal: true

require "tempfile"
require "lago/database/schema_rewriter"

# Loads `db/structure.sql` into the schema configured with `POSTGRES_SCHEMA`.
#
# On an empty database, `db:migrate` and `db:prepare` load the structure file
# with `psql` before running any migration. The dump names `public` on every
# object, so without this patch a custom schema only gets the Rails metadata
# tables while every Lago table lands in `public`.
#
# When the first schema of the search path is not `public`, the file is
# rewritten by `Lago::Database::SchemaRewriter` into a temporary file, with the
# target schema created first.
module Lago
  module Database
    module StructureLoadPatch
      def structure_load(filename, extra_flags)
        schema = SchemaRewriter.target_schema(configuration_hash[:schema_search_path])
        return super if schema.nil?

        sql = SchemaRewriter.new(File.read(filename), schema:).call

        Tempfile.create(["structure", ".sql"]) do |file|
          file.write("CREATE SCHEMA IF NOT EXISTS #{PG::Connection.quote_ident(schema)};\n\n")
          file.write(sql)
          file.flush

          super(file.path, extra_flags)
        end
      end
    end
  end
end
