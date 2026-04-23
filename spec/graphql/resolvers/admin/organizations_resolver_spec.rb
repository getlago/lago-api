# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::Admin::OrganizationsResolver do
  let(:staff_email) { "miguel@getlago.com" }
  let(:staff_user) { create(:user, email: staff_email) }
  let(:membership) { create(:membership, user: staff_user) }

  let(:query) do
    <<~GQL
      query($searchTerm: String) {
        adminOrganizations(searchTerm: $searchTerm, limit: 25) {
          collection { id name }
        }
      }
    GQL
  end

  before do
    membership
    stub_const("AuthenticableStaffUser::STAFF_ALLOWED_EMAILS", [staff_email].freeze)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LAGO_STAFF_ALLOWED_EMAILS").and_return(nil)
  end

  it "returns all organizations matching the search term across tenants" do
    create(:organization, name: "Acme Inc")
    create(:organization, name: "Beta Corp")

    result = execute_graphql(
      current_user: staff_user,
      current_organization: membership.organization,
      query: query,
      variables: {searchTerm: "Acme"}
    )

    names = result["data"]["adminOrganizations"]["collection"].map { |o| o["name"] }
    expect(names).to include("Acme Inc")
    expect(names).not_to include("Beta Corp")
  end

  it "rejects non-staff users" do
    outsider = create(:user, email: "outsider@getlago.com")
    create(:membership, user: outsider)

    result = execute_graphql(
      current_user: outsider,
      current_organization: outsider.organizations.first,
      query: query,
      variables: {searchTerm: "Acme"}
    )

    expect_graphql_error(result: result, message: "not_staff_member")
  end
end
