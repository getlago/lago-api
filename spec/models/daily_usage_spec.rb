# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyUsage do
  subject(:daily_usage) { build(:daily_usage) }

  describe "associations" do
    it do
      expect(daily_usage).to belong_to(:organization)
      expect(daily_usage).to belong_to(:customer)
      expect(daily_usage).to belong_to(:subscription).optional
      expect(daily_usage).to belong_to(:contract).optional
      expect(daily_usage).to belong_to(:contract_rate_card).optional
    end
  end

  describe "subscription or contract check" do
    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }

    it "accepts a subscription daily usage" do
      expect(create(:daily_usage, customer:)).to be_persisted
    end

    it "accepts a contract daily usage" do
      expect(create(:daily_usage, :contract, customer:)).to be_persisted
    end

    it "refuses a daily usage with both a subscription and a contract" do
      daily_usage = build(:daily_usage, :contract, customer:, subscription: create(:subscription, customer:))
      daily_usage.external_subscription_id = daily_usage.subscription.external_id

      expect { daily_usage.save! }.to raise_error(ActiveRecord::CheckViolation, /daily_usages_subscription_or_contract/)
    end

    it "refuses a daily usage with neither a subscription nor a contract" do
      daily_usage = build(:daily_usage, customer:, subscription: nil, external_subscription_id: nil)

      expect { daily_usage.save! }.to raise_error(ActiveRecord::CheckViolation, /daily_usages_subscription_or_contract/)
    end

    it "refuses a contract daily usage without its rate card" do
      daily_usage = build(:daily_usage, :contract, customer:, contract_rate_card: nil)

      expect { daily_usage.save! }.to raise_error(ActiveRecord::CheckViolation, /daily_usages_subscription_or_contract/)
    end

    it "refuses a rate card of another contract" do
      other_contract = create(:contract, organization:, customer:)
      daily_usage = build(:daily_usage, :contract, customer:)
      daily_usage.contract_rate_card = create(:contract_rate_card, organization:, contract: other_contract)

      expect { daily_usage.save! }.to raise_error(ActiveRecord::InvalidForeignKey, /fk_daily_usages_contract_rate_card_contract/)
    end
  end
end
