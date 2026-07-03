# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Superset::CreateGuestToken do
  let(:required_permission) { "analytics:view" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:dashboard_id) { "42" }
  let(:guest_token) { "fresh-guest-token" }

  let(:mutation) do
    <<~GQL
      mutation($input: CreateSupersetGuestTokenInput!) {
        createSupersetGuestToken(input: $input) {
          guestToken
        }
      }
    GQL
  end

  let(:result) do
    BaseService::Result.new.tap { |r| r.guest_token = guest_token }
  end

  before do
    allow(Auth::Superset::GuestTokenService).to receive(:call).and_return(result)
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "analytics:view"

  it "returns a fresh guest token for the given dashboard" do
    graphql_result = execute_graphql(
      current_user: membership.user,
      current_organization: organization,
      permissions: required_permission,
      query: mutation,
      variables: {input: {dashboardId: dashboard_id}}
    )

    expect(graphql_result["data"]["createSupersetGuestToken"]["guestToken"]).to eq(guest_token)

    expect(Auth::Superset::GuestTokenService).to have_received(:call).with(
      organization: organization,
      dashboard_id: dashboard_id,
      user: nil
    )
  end

  context "when the superset service fails" do
    let(:result) do
      BaseService::Result.new.tap do |r|
        r.service_failure!(code: "superset_guest_token_failed", message: "Failed to mint guest token")
      end
    end

    it "returns an error" do
      graphql_result = execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query: mutation,
        variables: {input: {dashboardId: dashboard_id}}
      )

      expect(graphql_result["errors"]).to be_present
      expect(graphql_result["errors"].first["extensions"]["code"]).to eq("superset_guest_token_failed")
    end
  end
end
