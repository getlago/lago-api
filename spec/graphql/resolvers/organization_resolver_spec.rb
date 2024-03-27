# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::OrganizationResolver, type: :graphql do
  let(:query) do
    <<~GQL
      query {
        organization {
          id
          name
        }
      }
    GQL
  end

  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }

  it "returns the current organization" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      query:,
      variables: {}
    )

    data = result["data"]["organization"]

    aggregate_failures do
      expect(data["id"]).to eq(organization.id)
      expect(data["name"]).to eq(organization.name)
    end
  end
end
