# frozen_string_literal: true

require "rails_helper"

RSpec.describe CsAdminAuditLog, type: :model do
  subject(:audit_log) { build(:cs_admin_audit_log) }

  describe "enums" do
    it do
      is_expected.to define_enum_for(:action)
        .with_values(toggle_on: 0, toggle_off: 1, org_created: 2, rollback: 3)
        .validating

      is_expected.to define_enum_for(:feature_type)
        .with_values(premium_integration: 0, feature_flag: 1)
        .validating
    end
  end

  describe "associations" do
    it do
      is_expected.to belong_to(:actor_user).class_name("User")
      is_expected.to belong_to(:organization)
      is_expected.to belong_to(:rollback_of).class_name("CsAdminAuditLog").optional
    end
  end

  describe "Scopes" do
    describe ".newest_first" do
      let(:org) { create(:organization) }
      let!(:log1) { create(:cs_admin_audit_log, organization: org, created_at: 1.day.ago) }
      let!(:log2) { create(:cs_admin_audit_log, organization: org, created_at: Time.current) }

      it "orders by newest first" do
        expect(CsAdminAuditLog.newest_first.to_a).to eq([log2, log1])
      end
    end
  end

  describe "validations" do
    it do
      is_expected.to validate_presence_of(:actor_email)
      is_expected.to validate_presence_of(:action)
      is_expected.to validate_presence_of(:feature_type)
      is_expected.to validate_presence_of(:feature_key)
      is_expected.to validate_presence_of(:reason)
      is_expected.to validate_length_of(:reason).is_at_least(10).is_at_most(500)
    end
  end
end
