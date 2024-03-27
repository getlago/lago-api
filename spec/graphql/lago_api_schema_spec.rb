# frozen_string_literal: true

require "rails_helper"

RSpec.describe LagoApiSchema do
  it "matches the dumped schema" do
    aggregate_failures do
      expect(described_class.to_definition.rstrip).to eq(File.read(Rails.root.join("schema.graphql")).rstrip)
      expect(described_class.to_json.rstrip).to eq(File.read(Rails.root.join("schema.json")).rstrip)
    end
  end
end
