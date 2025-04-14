# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::RecalculateUsageService do
  subject(:calculate_service) { described_class.new(subscription:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }

  let(:subscription) { create(:subscription, organization:, customer:, plan:) }

  describe "#call" do
    it "flags the lifetime usage for refresh" do
      create(:usage_threshold, plan:)

      calculate_service.call

      expect(subscription.reload.lifetime_usage).to be_present
      expect(subscription.lifetime_usage.recalculate_current_usage).to be(true)
    end
  end
end
