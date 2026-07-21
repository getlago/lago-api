# frozen_string_literal: true

require "rails_helper"
require "lago/rds_proxy/connection_patch"

RSpec.describe Lago::RdsProxy::ConnectionPatch do
  # Stub class mimicking PostgreSQLAdapter's interface for the methods our
  # patch interacts with. We assert on call ordering and absence of SETs.
  let(:adapter_class) do
    Class.new do
      attr_accessor :schema_search_path, :calls

      def initialize(config)
        @config = config
        @raw_connection = Object.new
        @notice_receiver_sql_warnings = []
        @pool = Object.new
        @calls = []
      end

      def check_version
        @calls << :check_version
      end

      def add_pg_encoders
        @calls << :add_pg_encoders
      end

      def add_pg_decoders
        @calls << :add_pg_decoders
      end

      def reload_type_map
        @calls << :reload_type_map
      end

      def internal_execute(sql, _name = nil)
        @calls << [:internal_execute, sql]
      end

      def quote(value)
        "'#{value}'"
      end

      def reconfigure_connection_timezone
        @calls << :original_reconfigure_connection_timezone
      end

      prepend Lago::RdsProxy::ConnectionPatch
    end
  end

  let(:adapter) { adapter_class.new(config) }

  before { allow(ActiveRecord).to receive(:db_warnings_action).and_return(nil) }

  describe "#configure_connection" do
    context "with a basic config" do
      let(:config) { {schema_search_path: "public"} }

      before { adapter.configure_connection }

      it "calls check_version" do
        expect(adapter.calls).to include(:check_version)
      end

      it "caches the schema_search_path from config" do
        expect(adapter.schema_search_path).to eq("public")
      end

      it "calls add_pg_encoders, add_pg_decoders and reload_type_map" do
        expect(adapter.calls).to include(:add_pg_encoders, :add_pg_decoders, :reload_type_map)
      end

      it "does not send any SET commands" do
        sets = adapter.calls.select { |c| c.is_a?(Array) && c[0] == :internal_execute }
        expect(sets).to be_empty
      end
    end

    context "with no schema_search_path in config" do
      let(:config) { {} }

      it "leaves @schema_search_path nil for the lazy getter to populate" do
        adapter.configure_connection
        expect(adapter.schema_search_path).to be_nil
      end
    end

    context "with schema_order fallback" do
      let(:config) { {schema_order: "tenant_a,public"} }

      it "uses schema_order when schema_search_path is absent" do
        adapter.configure_connection
        expect(adapter.schema_search_path).to eq("tenant_a,public")
      end
    end

    context "with user-defined variables" do
      let(:config) { {variables: {statement_timeout: "30s", lock_timeout: :default}} }

      before { adapter.configure_connection }

      it "does not emit SET SESSION for variables (they pin the connection on RDS Proxy)" do
        sets = adapter.calls.select { |c| c.is_a?(Array) && c[0] == :internal_execute }
        expect(sets).to be_empty
      end
    end
  end

  describe "#reconfigure_connection_timezone" do
    let(:config) { {} }

    it "is a no-op so add_pg_decoders does not emit SET SESSION timezone" do
      adapter.send(:reconfigure_connection_timezone)
      expect(adapter.calls).not_to include(:original_reconfigure_connection_timezone)
    end
  end

  # The specs above use a fake adapter to assert call ordering / absence of SETs
  # in isolation. This block exercises the REAL PostgreSQLAdapter against the test
  # database, so we catch any drift in `configure_connection`'s internals across
  # Rails upgrades (per review feedback: the fake could hide such a change).
  describe "against the real PostgreSQLAdapter" do
    let(:db_config) { ActiveRecord::Base.connection_db_config.configuration_hash }

    # Plain adapter = control; the patched one uses an isolated subclass so the
    # prepend never leaks onto the shared connection pool.
    let(:plain_adapter) do
      ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.new(db_config)
    end

    let(:patched_adapter) do
      Class.new(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter) do
        prepend Lago::RdsProxy::ConnectionPatch
      end.new(db_config)
    end

    after do
      plain_adapter.disconnect!
      patched_adapter.disconnect!
    end

    # Rails' configure_connection drives these away from the Postgres server
    # defaults; the patch must leave them alone. Asserting "not the Rails value"
    # (rather than a hardcoded default) keeps this robust across environments.
    it "applies Rails' session SETs without the patch (control)" do
      expect(plain_adapter.select_value("SHOW intervalstyle")).to eq("iso_8601")
      expect(plain_adapter.select_value("SHOW client_min_messages")).to eq("warning")
    end

    it "skips the session SETs and keeps the connection fully functional" do
      expect(patched_adapter.select_value("SHOW intervalstyle")).not_to eq("iso_8601")
      expect(patched_adapter.select_value("SHOW client_min_messages")).not_to eq("warning")

      # Connection is usable and decoders are loaded (integers cast, not raw strings):
      expect(patched_adapter.select_value("SELECT 1")).to eq(1)
    end
  end
end
