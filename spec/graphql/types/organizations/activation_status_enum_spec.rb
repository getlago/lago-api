# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Organizations::ActivationStatusEnum do
  it "has the organization activation statuses" do
    expect(described_class.graphql_name).to eq("OrganizationActivationStatusEnum")
    expect(described_class.values.keys).to eq(Organization::ACTIVATION_STATUSES.values)
  end
end
