# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Admin::RollbackChange do
  let(:query) do
    <<~GQL
      mutation($input: AdminRollbackChangeInput!) {
        adminRollbackChange(input: $input) {
          id action featureKey beforeValue afterValue rollbackOfId
        }
      }
    GQL
  end

  let(:admin_user) { create(:user, email: "cs@getlago.com", cs_admin: true) }
  let(:organization) { create(:organization, premium_integrations: ["okta"]) }

  let(:audit_log) do
    create(
      :cs_admin_audit_log,
      actor_user: admin_user,
      organization:,
      action: :toggle_on,
      feature_type: :premium_integration,
      feature_key: "okta",
      before_value: false,
      after_value: true
    )
  end

  def rollback(current_user: admin_user, audit_log_id: audit_log.id)
    execute_graphql(
      current_user:,
      query:,
      variables: {input: {auditLogId: audit_log_id, reason: "Rolling back the okta toggle"}}
    )
  end

  it "reverses the change and returns the rollback log", :premium do
    result = rollback

    log = result["data"]["adminRollbackChange"]
    expect(log["action"]).to eq("rollback")
    expect(log["featureKey"]).to eq("okta")
    expect(log["beforeValue"]).to be(true)
    expect(log["afterValue"]).to be(false)
    expect(log["rollbackOfId"]).to eq(audit_log.id)

    expect(organization.reload.premium_integrations).not_to include("okta")
  end

  context "when the audit log does not exist", :premium do
    it "returns a not found error" do
      result = rollback(audit_log_id: SecureRandom.uuid)

      expect_graphql_error(result:, message: "not_found")
    end
  end

  context "when the audit log is an organization creation", :premium do
    let(:audit_log) do
      create(
        :cs_admin_audit_log,
        actor_user: admin_user,
        organization:,
        action: :org_created,
        feature_type: :organization,
        feature_key: "organization",
        before_value: nil,
        after_value: true
      )
    end

    it "returns a validation error" do
      result = rollback

      expect_graphql_error(result:, message: "unprocessable_entity")
      expect(CsAdminAuditLog.where(action: :rollback)).to be_empty
    end
  end

  context "when the license is not premium" do
    it "returns an unauthorized error" do
      result = rollback

      expect_graphql_error(result:, message: "unauthorized")
      expect(CsAdminAuditLog.where(action: :rollback)).to be_empty
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
