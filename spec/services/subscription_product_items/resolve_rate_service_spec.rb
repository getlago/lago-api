# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionProductItems::ResolveRateService do
  subject(:result) { described_class.call(subscription_product_item:, datetime:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:) }
  let(:product_item) { create(:product_item, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product_item:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:subscription_product_item) { create(:subscription_product_item, organization:, subscription:, product_item:) }

  let!(:plan_product_item) { create(:plan_product_item, organization:, plan:, product_item:, rate_card:) }

  let!(:january_rate) { create(:rate_card_rate, organization:, rate_card:, effective_datetime: Time.utc(2026, 1, 1)) }
  let!(:july_rate) { create(:rate_card_rate, organization:, rate_card:, effective_datetime: Time.utc(2026, 7, 1)) }

  context "when several rates are effective on or before the datetime" do
    let(:datetime) { Time.utc(2026, 8, 1) }

    it "returns the latest active rate" do
      expect(result).to be_success
      expect(result.rate).to eq(july_rate)
    end
  end

  context "when only the earlier rate is effective" do
    let(:datetime) { Time.utc(2026, 3, 1) }

    it "returns the earlier rate, not the future one" do
      expect(result.rate).to eq(january_rate)
    end
  end

  context "when no rate is effective yet" do
    let(:datetime) { Time.utc(2025, 12, 1) }

    it "fails with a rate not found error" do
      expect(result).not_to be_success
      expect(result.error).to be_a(BaseService::NotFoundFailure)
    end
  end
end
