# frozen_string_literal: true

require "rails_helper"

RSpec.describe Schemas::CustomerPortalSchema do
  it "matches the dumped schema" do
    aggregate_failures do
      expect(described_class.to_definition.rstrip).to eq(File.read(Rails.root.join("graphql_schemas/customer_portal.graphql")).rstrip)
      expect(described_class.to_json.rstrip).to eq(File.read(Rails.root.join("graphql_schemas/customer_portal.json")).rstrip)
    end
  end
end
