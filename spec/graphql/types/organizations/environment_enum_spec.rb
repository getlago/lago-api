# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Organizations::EnvironmentEnum do
  it "has the organization environments" do
    expect(described_class.graphql_name).to eq("OrganizationEnvironmentEnum")
    expect(described_class.values.keys).to eq(Organization::ENVIRONMENTS.values)
  end
end
