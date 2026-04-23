# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::PremiumIntegrations::ToggleService, clickhouse: true do
  subject(:result) do
    described_class.call(
      organization: organization,
      integration: integration,
      enabled: enabled,
      reason: reason,
      reason_category: reason_category,
      user: user,
      staff_role: staff_role
    )
  end

  let(:organization) { create(:organization, premium_integrations: []) }
  let(:user) { create(:user) }
  let(:integration) { "revenue_analytics" }
  let(:enabled) { true }
  let(:reason) { "customer requested during demo" }
  let(:reason_category) { "sales_demo" }
  let(:staff_role) { :admin }

  describe "#call" do
    context "when an admin enables a valid integration" do
      it "adds it to premium_integrations and returns the activity log" do
        expect(result).to be_success
        expect(organization.reload.premium_integrations).to include("revenue_analytics")
        expect(result.activity_log).to be_present
      end

      it "writes a Clickhouse activity log with category + role" do
        expect { result }.to change(Clickhouse::ActivityLog, :count).by(1)

        log = Clickhouse::ActivityLog.order(logged_at: :desc).first
        changes = log.activity_object_changes.transform_values { |v| JSON.parse(v) }
        expect(changes["reason_category"]).to eq("sales_demo")
        expect(changes["staff_role"]).to eq("admin")
      end

      it "enqueues a Slack notify job when the webhook is configured" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("LAGO_STAFF_SLACK_WEBHOOK").and_return("https://hooks.slack.test/abc")

        expect { result }.to have_enqueued_job(Admin::PremiumIntegrations::NotifySlackJob)
      end

      it "does not enqueue a Slack job when no webhook is configured" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("LAGO_STAFF_SLACK_WEBHOOK").and_return(nil)

        expect { result }.not_to have_enqueued_job(Admin::PremiumIntegrations::NotifySlackJob)
      end
    end

    context "when a CS user toggles a permitted integration" do
      let(:staff_role) { :cs }
      let(:integration) { "revenue_analytics" }

      it "succeeds" do
        expect(result).to be_success
      end
    end

    context "when a CS user toggles a restricted integration" do
      let(:staff_role) { :cs }
      let(:integration) { "netsuite" }

      it "is forbidden with integration_not_allowed_for_role" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("integration_not_allowed_for_role")
      end
    end

    context "when the integration is not in PREMIUM_INTEGRATIONS" do
      let(:integration) { "definitely_not_real" }

      it "fails with invalid_integration" do
        expect(result).not_to be_success
        expect(result.error.messages[:integration]).to include("invalid_integration")
      end
    end

    context "when reason is blank" do
      let(:reason) { "  " }

      it "fails with value_is_mandatory" do
        expect(result).not_to be_success
        expect(result.error.messages[:reason]).to include("value_is_mandatory")
      end
    end

    context "when reason_category is unknown" do
      let(:reason_category) { "pineapple" }

      it "fails with invalid_reason_category" do
        expect(result).not_to be_success
        expect(result.error.messages[:reason_category]).to include("invalid_reason_category")
      end
    end

    context "when the flag state already matches" do
      let(:organization) { create(:organization, premium_integrations: ["revenue_analytics"]) }

      it "is a no-op (no log, no slack)" do
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with("LAGO_STAFF_SLACK_WEBHOOK").and_return("https://hooks.slack.test/abc")

        expect { result }.not_to change(Clickhouse::ActivityLog, :count)
        expect { result }.not_to have_enqueued_job(Admin::PremiumIntegrations::NotifySlackJob)
        expect(result).to be_success
      end
    end
  end
end
