# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Admin::BatchToggleFeature do
  let(:query) do
    <<~GQL
      mutation($input: AdminBatchToggleFeatureInput!) {
        adminBatchToggleFeature(input: $input) {
          id action featureType featureKey organizationId batchId
        }
      }
    GQL
  end

  let(:admin_user) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:organization) { create(:organization) }
  let(:other_organization) { create(:organization) }
  let(:organization_ids) { [organization.id, other_organization.id] }

  def toggle(current_user: admin_user, ids: organization_ids, feature_key: "okta")
    execute_graphql(
      current_user:,
      query:,
      variables: {
        input: {
          organizationIds: ids,
          featureType: "premium_integration",
          featureKey: feature_key,
          enabled: true,
          reason: "Enabling okta for the POC of both accounts",
          notifyOrgAdmin: false
        }
      }
    )
  end

  it "toggles the feature on every organization of the batch" do
    result = toggle

    logs = result["data"]["adminBatchToggleFeature"]
    expect(logs.map { |log| log["organizationId"] }).to match_array(organization_ids)
    expect(logs.map { |log| log["action"] }.uniq).to eq(["toggle_on"])
    expect(logs.map { |log| log["batchId"] }.uniq.count).to eq(1)

    expect(organization.reload.premium_integrations).to include("okta")
    expect(other_organization.reload.premium_integrations).to include("okta")
  end

  context "when an organization id matches no organization" do
    let(:unknown_id) { SecureRandom.uuid }

    it "returns a validation error naming the unknown ids" do
      result = toggle(ids: [organization.id, unknown_id])

      expect_graphql_error(result:, message: "unprocessable_entity")
      expect(result["errors"].first["extensions"]["details"]["organizationIds"])
        .to eq(["#{unknown_id}: not_found"])
    end

    it "does not toggle the feature on the organizations that matched" do
      expect { toggle(ids: [organization.id, unknown_id]) }.not_to change(CsAdminAuditLog, :count)

      expect(organization.reload.premium_integrations).not_to include("okta")
    end
  end

  context "when one of the toggles fails" do
    let(:failed_result) do
      ::Admin::ToggleFeatureService::Result.new.validation_failure!(errors: {feature_key: ["invalid"]})
    end

    before do
      # The first organization is toggled for real, the second one fails.
      processed = 0
      allow(::Admin::ToggleFeatureService).to receive(:call).and_wrap_original do |original, **kwargs|
        processed += 1

        if processed == 1
          original.call(**kwargs)
        else
          failed_result
        end
      end
    end

    it "returns the error and rolls the whole batch back" do
      result = toggle

      expect_graphql_error(result:, message: "unprocessable_entity")

      expect(CsAdminAuditLog.count).to eq(0)
      expect(organization.reload.premium_integrations).not_to include("okta")
      expect(other_organization.reload.premium_integrations).not_to include("okta")
      expect(Admin::SlackNotificationJob).not_to have_been_enqueued
      expect(Admin::EmailNotificationJob).not_to have_been_enqueued
    end
  end

  context "when the user is not a CS admin" do
    let(:regular_user) { create(:user, email: "user@acme.test") }

    it "returns an unauthorized error" do
      result = toggle(current_user: regular_user)

      expect_graphql_error(result:, message: "unauthorized")
    end
  end
end
