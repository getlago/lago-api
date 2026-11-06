# frozen_string_literal: true

require "rails_helper"

RSpec.describe LagoApiSchema do
  it "rejects retired forecast queries before executing a resolver" do
    errors = described_class.validate("{ dataApiUsagesForecasted { collection { amountCents } } }")

    expect(errors.map { |error| error.to_h.dig("extensions", "code") }).to include("undefinedField")
  end

  it "matches the dumped graphql schema" do
    expect(described_class.to_definition.rstrip).to eq(File.read(Rails.root.join("schema.graphql")).rstrip)
  end

  it "matches the dumped JSON schema" do
    actual_json_schema = JSON.parse(described_class.to_json)
    expected_json_schema = JSON.parse(File.read(Rails.root.join("schema.json")))

    expect(actual_json_schema).to eq(expected_json_schema)
  end

  describe ".introspection_enabled?" do
    it "is enabled in development and test" do
      %w[development test].each do |env|
        inquirer = ActiveSupport::EnvironmentInquirer.new(env)

        expect(described_class.introspection_enabled?(env: inquirer, flag: nil)).to be(true)
      end
    end

    it "is disabled in other environments unless the flag is set" do
      production = ActiveSupport::EnvironmentInquirer.new("production")

      expect(described_class.introspection_enabled?(env: production, flag: nil)).to be(false)
      expect(described_class.introspection_enabled?(env: production, flag: "false")).to be(false)
      expect(described_class.introspection_enabled?(env: production, flag: "true")).to be(true)
    end
  end

  context "with introspection disabled" do
    let(:schema) do
      Class.new(described_class) do
        disable_introspection_entry_points
        did_you_mean nil
      end
    end

    it "rejects __schema and __type" do
      schema_errors = schema.execute("{ __schema { queryType { name } } }")["errors"]
      type_errors = schema.execute('{ __type(name: "Query") { name } }')["errors"]

      expect(schema_errors.first["message"]).to include("__schema")
      expect(type_errors.first["message"]).to include("__type")
    end

    it "does not suggest field names" do
      query = "{ organizatio { id } }"

      expect(described_class.execute(query)["errors"].first["message"]).to include("Did you mean")
      expect(schema.execute(query)["errors"].first["message"]).not_to include("Did you mean")
    end

    it "still resolves __typename" do
      result = schema.execute("{ __typename }")

      expect(result["errors"]).to be_nil
      expect(result.dig("data", "__typename")).to eq("Query")
    end
  end
end
