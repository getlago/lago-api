# frozen_string_literal: true

require "rails_helper"

RSpec.describe AdminMailer do
  describe "#feature_toggled" do
    subject(:mail) { described_class.feature_toggled(audit_log:, actor_email: "cs@getlago.com") }

    let(:organization) { create(:organization, name: "Hooli Inc") }
    let(:owner) { create(:user, email: "owner@hooli.test") }
    let(:admin_membership) { create(:membership, organization:, user: owner, roles: [:admin]) }

    let(:audit_log) do
      create(
        :cs_admin_audit_log,
        organization:,
        action: :toggle_on,
        feature_type: :premium_integration,
        feature_key: "okta"
      )
    end

    before do
      admin_membership

      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_FROM_EMAIL").and_return("noreply@getlago.com")
    end

    it "is sent from the Lago sender to the organization admin" do
      expect(mail.from).to eq(["noreply@getlago.com"])
      expect(mail.to).to eq(["owner@hooli.test"])
      expect(mail.subject).to eq("Feature okta has been enabled on your organization")
    end

    it "includes the organization, the feature and the actor in the body" do
      body = mail.body.to_s

      expect(body).to include("Hooli Inc")
      expect(body).to include("okta")
      expect(body).to include("cs@getlago.com")
    end

    context "when the feature was toggled off" do
      let(:audit_log) do
        create(
          :cs_admin_audit_log,
          organization:,
          action: :toggle_off,
          feature_type: :premium_integration,
          feature_key: "okta",
          before_value: true,
          after_value: false
        )
      end

      it "announces the feature as disabled" do
        expect(mail.subject).to eq("Feature okta has been disabled on your organization")
      end
    end

    context "when the organization has several admins" do
      let(:earliest_owner) { create(:user, email: "first@hooli.test", created_at: 1.year.ago) }

      before { create(:membership, organization:, user: earliest_owner, roles: [:admin]) }

      it "always notifies the oldest admin" do
        expect(mail.to).to eq(["first@hooli.test"])
      end
    end

    context "when the organization has no admin" do
      let(:admin_membership) { create(:membership, organization:, roles: [:manager]) }

      it "does not build a message" do
        expect(mail.to).to be_nil
      end
    end
  end
end
