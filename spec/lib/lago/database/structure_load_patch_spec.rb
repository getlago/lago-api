# frozen_string_literal: true

require "rails_helper"
require "lago/database/structure_load_patch"

RSpec.describe Lago::Database::StructureLoadPatch do
  let(:database_tasks) { ActiveRecord::Tasks::PostgreSQLDatabaseTasks.new(db_config) }

  let(:db_config) do
    ActiveRecord::DatabaseConfigurations::HashConfig.new(
      "production",
      "primary",
      {adapter: "postgresql", database: "lago", schema_search_path:}
    )
  end
  let(:schema_search_path) { "public" }
  let(:structure_file) do
    Tempfile.create(["structure", ".sql"]).tap do |file|
      file.write("CREATE TABLE public.customers (id bigint);\n")
      file.flush
    end
  end
  let(:loaded) { {} }

  before do
    allow(database_tasks).to receive(:run_cmd) do |cmd, args, _action|
      loaded[:cmd] = cmd
      loaded[:file] = args[args.index("--file") + 1]
      loaded[:sql] = File.read(loaded[:file])
    end
  end

  after { File.delete(structure_file.path) }

  it "is prepended to the PostgreSQL database tasks" do
    expect(ActiveRecord::Tasks::PostgreSQLDatabaseTasks.ancestors).to include(described_class)
  end

  context "with a custom schema" do
    let(:schema_search_path) { "lago,public" }

    it "loads the structure into the schema" do
      database_tasks.structure_load(structure_file.path, nil)

      expect(loaded[:cmd]).to eq("psql")
      expect(loaded[:sql]).to eq("CREATE SCHEMA IF NOT EXISTS \"lago\";\n\nCREATE TABLE \"lago\".customers (id bigint);\n")
    end

    it "removes the rewritten file" do
      database_tasks.structure_load(structure_file.path, nil)

      expect(File.exist?(loaded[:file])).to be(false)
    end
  end

  context "with the public schema" do
    it "loads the structure file as it is" do
      database_tasks.structure_load(structure_file.path, nil)

      expect(loaded[:file]).to eq(structure_file.path)
    end
  end
end
