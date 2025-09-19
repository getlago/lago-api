# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscriptions::FlagRefreshedService do
  subject(:flag_service) { described_class.new(subscription.id) }

  let(:organization) { create(:organization, premium_integrations: %w[lifetime_usage]) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:wallet) { create(:wallet, customer:, ready_to_be_refreshed: false) }

  before do
    wallet
  end

  around { |test| lago_premium!(&test) }

  describe "#call" do
    it "flags the wallets and usage for refresh" do
      result = flag_service.call

      expect(result).to be_success
      expect(wallet.reload).to be_ready_to_be_refreshed
      expect(subscription.subscription_activity).to be_present
    end
  end
end
