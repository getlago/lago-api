# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionRateCardsQuery, type: :query do
  subject(:result) { described_class.call(organization:, pagination:, filters:) }

  let(:organization) { create(:organization) }
  let(:pagination) { nil }
  let(:filters) { {} }

  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:, organization:) }
  let!(:subscription_rate_card) { create(:subscription_rate_card, organization:, subscription:) }
  let!(:other_subscription_rate_card) { create(:subscription_rate_card, organization:) }

  it "returns all subscription product items of the organization" do
    expect(result).to be_success
    expect(result.subscription_rate_cards).to match_array([subscription_rate_card, other_subscription_rate_card])
  end

  context "when filtering by subscription_id" do
    let(:filters) { {subscription_id: subscription.id} }

    it "returns only the subscription's product items" do
      expect(result.subscription_rate_cards).to eq([subscription_rate_card])
    end
  end

  context "when filtering by external_subscription_id" do
    let(:filters) { {external_subscription_id: subscription.external_id} }

    it "returns only the subscription's product items" do
      expect(result.subscription_rate_cards).to eq([subscription_rate_card])
    end
  end
end
