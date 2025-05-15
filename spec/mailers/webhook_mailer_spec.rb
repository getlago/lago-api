# frozen_string_literal: true

require "rails_helper"

RSpec.describe WebhookMailer, type: :mailer do
  describe "#failure_notification" do
    subject(:mail) { described_class.with(webhook:).failure_notification }

    let(:organization) { create(:organization, name: "Test Org", email: "org1@example.com,org2@example.com") }
    let(:webhook_endpoint) { create(:webhook_endpoint, organization: organization) }
    let(:webhook) { create(:webhook, webhook_endpoint: webhook_endpoint, status: :failed, last_retried_at: 30.minutes.ago) }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("LAGO_FRONT_URL").and_return("https://app.lago.com")

      create_list(:webhook, 3, webhook_endpoint: webhook_endpoint, status: :failed, last_retried_at: 30.minutes.ago)
    end

    it "sends the email" do
      create(:membership, user: create(:user, email: "admin1@example.com"), organization:)
      create(:membership, user: create(:user, email: "admin2@example.com"), organization:)

      expect(mail.subject).to eq("[ALERT] Webhook delivery failed for Test Org")
      expect(mail.to).to match_array(["admin1@example.com", "admin2@example.com", "org1@example.com", "org2@example.com"])

      body = mail.body.encoded
      expect(body).to include("https://app.lago.com/developers/webhooks")
      expect(body).to include("There are currently 4 failed webhooks in the last hour.")
    end

    context "when organization has no admins" do
      it "only uses emails from the organization email field" do
        expect(mail.to).to match_array(["org1@example.com", "org2@example.com"])
      end
    end

    context "when organization email has whitespace" do
      let(:organization) { create(:organization, email: "org1@example.com, org2@example.com , org3@example.com") }

      it "handles whitespace in comma-separated emails" do
        expected_emails = ["org1@example.com", "org2@example.com", "org3@example.com"]
        expect(mail.to).to match_array(expected_emails)
      end
    end

    context "when organization no email" do
      let(:organization) { create(:organization, email: nil) }

      it "handles empty entries in comma-separated emails" do
        create(:membership, user: create(:user, email: "admin1@example.com"), organization:)
        expected_emails = ["admin1@example.com"]
        expect(mail.to).to match_array(expected_emails)
      end
    end

    context "when organization email has empty entries" do
      let(:organization) { create(:organization, email: "org1@example.com,,org2@example.com") }

      it "handles empty entries in comma-separated emails" do
        expected_emails = ["org1@example.com", "org2@example.com"]
        expect(mail.to).to match_array(expected_emails)
      end
    end

    it "delivers the email" do
      expect { mail.deliver_now }.to change { ActionMailer::Base.deliveries.count }.by(1)
      expect(ActionMailer::Base.deliveries.last).to eq(mail)
    end
  end
end
