# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Admin::BatchRollback do
  let(:query) do
    <<~GQL
      mutation($input: AdminBatchRollbackInput!) {
        adminBatchRollback(input: $input) {
          id action featureType featureKey afterValue rollbackOfId
        }
      }
    GQL
  end

  let(:admin_user) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:organization) { create(:organization, premium_integrations: ["okta"]) }
  let(:batch_id) { SecureRandom.uuid }

  let(:toggle_log) do
    create(
      :cs_admin_audit_log,
      actor_user: admin_user,
      organization:,
      action: :toggle_on,
      feature_type: :premium_integration,
      feature_key: "okta",
      before_value: false,
      after_value: true,
      batch_id:
    )
  end

  def rollback(current_user: admin_user, reason: "Rolling back the whole batch for support")
    execute_graphql(
      current_user:,
      query:,
      variables: {input: {batchId: batch_id, reason:}}
    )
  end

  it "rolls back every log of the batch" do
    toggle_log

    result = rollback

    logs = result["data"]["adminBatchRollback"]
    expect(logs.map { |log| log["rollbackOfId"] }).to eq([toggle_log.id])
    expect(logs.map { |log| log["action"] }).to eq(["rollback"])
    expect(organization.reload.premium_integrations).not_to include("okta")
  end

  context "when the batch contains an organization creation log" do
    let(:org_created_log) do
      create(
        :cs_admin_audit_log,
        actor_user: admin_user,
        organization:,
        action: :org_created,
        feature_type: :organization,
        feature_key: "organization",
        before_value: nil,
        after_value: true,
        batch_id:
      )
    end

    it "skips it and rolls back the remaining logs" do
      toggle_log
      org_created_log

      result = rollback

      logs = result["data"]["adminBatchRollback"]
      expect(logs.map { |log| log["rollbackOfId"] }).to eq([toggle_log.id])
      expect(CsAdminAuditLog.where(rollback_of: org_created_log)).to be_empty
    end
  end

  context "when the user is not a CS admin" do
    let(:regular_user) { create(:user, email: "user@acme.test") }

    it "returns an unauthorized error" do
      result = rollback(current_user: regular_user)

      expect_graphql_error(result:, message: "unauthorized")
    end
  end
end
