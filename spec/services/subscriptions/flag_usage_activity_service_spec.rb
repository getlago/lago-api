# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::FlagUsageActivityService, type: :service do
  subject(:service) { described_class.new(subscription:) }

  around { |test| lago_premium!(&test) }

  let(:subscription) { create(:subscription, :active, customer:, plan:) }

  let(:customer) { create(:customer) }
  let(:plan) { create(:plan, organization: customer.organization) }

  let(:usage_activity) { create(:subscription_usage_activity, subscription:, organization: customer.organization) }
  let(:threshold) { create(:usage_threshold, plan:) }

  before do
    usage_activity
    threshold
  end

  describe "#call" do
    it "flags the usage activity" do
      expect { service.call }
        .to change { usage_activity.reload.recalculate_current_usage }.from(false).to(true)
    end

    context "when usage activity does not exists" do
      let(:usage_activity) { nil }

      it "creates a new usage activity" do
        expect { service.call }
          .to change(subscription, :usage_activity)
          .from(nil).to(an_instance_of(Subscription::UsageActivity))
      end
    end

    context "when subscription is not active" do
      let(:subscription) { create(:subscription, :pending, customer:, plan:) }

      it "does not flag the usage activity" do
        expect { service.call }
          .not_to change { usage_activity.reload.recalculate_current_usage }
      end
    end

    context "when not thresholds exists" do
      let(:threshold) { nil }

      it "does not flag the usage activity" do
        expect { service.call }
          .not_to change { usage_activity.reload.recalculate_current_usage }
      end
    end

    context "when lifetime usage is active" do
      before do
        subscription.organization.update!(premium_integrations: ["lifetime_usage"])
      end

      it "flags the usage activity" do
        expect { service.call }
          .to change { usage_activity.reload.recalculate_current_usage }.from(false).to(true)
      end
    end

    context "when alerting_total_usage is active" do
      before do
        subscription.organization.update!(premium_integrations: ["alerting_total_usage"])
      end

      it "flags the usage activity" do
        expect { service.call }
          .to change { usage_activity.reload.recalculate_current_usage }.from(false).to(true)
      end
    end
  end
end
