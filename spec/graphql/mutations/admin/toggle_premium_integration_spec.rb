# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Admin::TogglePremiumIntegration, clickhouse: true do
  let(:staff_email) { "miguel@getlago.com" }
  let(:non_staff_email) { "intruder@getlago.com" }
  let(:target_organization) { create(:organization, premium_integrations: []) }
  let(:staff_user) { create(:user, email: staff_email) }
  let(:own_org) { create(:organization) }
  let(:membership) { create(:membership, user: staff_user, organization: own_org) }

  let(:mutation) do
    <<~GQL
      mutation($input: AdminTogglePremiumIntegrationInput!) {
        adminTogglePremiumIntegration(input: $input) {
          id
          premiumIntegrations
        }
      }
    GQL
  end

  before do
    membership
    stub_const(
      "AuthenticableStaffUser::STAFF_ALLOWED_EMAILS",
      [staff_email].freeze
    )
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LAGO_STAFF_ALLOWED_EMAILS").and_return(nil)
  end

  def run(user:, organization:)
    execute_graphql(
      current_user: user,
      current_organization: organization,
      query: mutation,
      variables: {
        input: {
          organizationId: target_organization.id,
          integration: "revenue_analytics",
          enabled: true,
          reason: "demo"
        }
      }
    )
  end

  context "without a current user" do
    it "returns unauthorized" do
      result = run(user: nil, organization: own_org)
      expect_unauthorized_error(result)
    end
  end

  context "with a non-staff user" do
    let(:staff_user) { create(:user, email: non_staff_email) }

    it "returns not_staff_member" do
      result = run(user: staff_user, organization: own_org)
      expect_graphql_error(result: result, message: "not_staff_member")
    end
  end

  context "with a staff user" do
    it "toggles the integration on the target organization" do
      result = run(user: staff_user, organization: own_org)

      expect(result["errors"]).to be_nil
      data = result["data"]["adminTogglePremiumIntegration"]
      expect(data["id"]).to eq(target_organization.id)
      expect(data["premiumIntegrations"]).to include("revenue_analytics")
    end

    it "writes an audit log" do
      expect { run(user: staff_user, organization: own_org) }
        .to change(Clickhouse::ActivityLog, :count).by(1)

      log = Clickhouse::ActivityLog.order(logged_at: :desc).first
      expect(log.activity_type).to eq("organization.premium_integration_toggled")
      expect(log.user_id).to eq(staff_user.id)
    end
  end
end
