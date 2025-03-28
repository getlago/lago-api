# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::FlagRefreshedService, type: :service do
  subject(:flag_service) { described_class.new(subscription_id) }

  let(:subscription_id) { subscription.id }

  let(:plan) { create(:plan, organization: customer.organization) }
  let(:threshold) { create(:usage_threshold, plan:) }

  let(:customer) { create(:customer) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:wallet) { create(:wallet, customer:, ready_to_be_refreshed: false) }

  before do
    wallet
    threshold
  end

  describe "#call" do
    it "flags the wallets and usage for refresh" do
      result = flag_service.call

      expect(result).to be_success
      expect(wallet.reload).to be_ready_to_be_refreshed
      expect(subscription.reload.lifetime_usage).to be_recalculate_current_usage
    end
  end
end
