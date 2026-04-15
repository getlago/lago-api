# frozen_string_literal: true

# Patches PostgreSQLAdapter#configure_connection to skip session-level SET
# commands that cause RDS Proxy to pin the connection. The skipped settings
# must be configured via the proxy's initQuery instead:
#
#   SET client_encoding = 'UTF8';
#   SET client_min_messages TO 'warning';
#   SET search_path TO 'public';
#   SET standard_conforming_strings = on;
#   SET intervalstyle = iso_8601;
#   SET timezone TO 'UTC'
#
# `@schema_search_path` is cached locally to avoid an extra `SHOW search_path`
# query on first access. This assumes the proxy's initQuery sets a `search_path`
# matching `@config[:schema_search_path]` (both default to 'public').
#
# `reconfigure_connection_timezone` is overridden to a no-op because it is
# invoked by `add_pg_decoders` during type map setup and would otherwise emit
# `SET SESSION timezone TO 'UTC'`.
#
# See: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy-pinning.html
module Lago
  module RdsProxy
    module ConnectionPatch
      def configure_connection
        check_version

        @schema_search_path = @config[:schema_search_path] || @config[:schema_order]

        unless ActiveRecord.db_warnings_action.nil?
          @raw_connection.set_notice_receiver do |result|
            message = result.error_field(PG::Result::PG_DIAG_MESSAGE_PRIMARY)
            code = result.error_field(PG::Result::PG_DIAG_SQLSTATE)
            level = result.error_field(PG::Result::PG_DIAG_SEVERITY)
            @notice_receiver_sql_warnings << SQLWarning.new(message, code, level, nil, @pool)
          end
        end

        # User-defined variables from database.yml will still pin the connection.
        variables = @config.fetch(:variables, {}).stringify_keys
        variables.each do |k, v|
          if v == ":default" || v == :default
            internal_execute("SET SESSION #{k} TO DEFAULT", "SCHEMA")
          elsif !v.nil?
            internal_execute("SET SESSION #{k} TO #{quote(v)}", "SCHEMA")
          end
        end

        add_pg_encoders
        add_pg_decoders
        reload_type_map
      end

      private

      def reconfigure_connection_timezone
        # no-op: proxy's initQuery sets the timezone
      end
    end
  end
end
