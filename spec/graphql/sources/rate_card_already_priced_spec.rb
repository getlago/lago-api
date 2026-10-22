# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sources::RateCardAlreadyPriced do
  let(:organization) { create(:organization) }
  let(:product) { create(:product, organization:) }
  let(:product_filter) { create(:product_filter, organization:, product:) }
  let(:default_card) { create(:rate_card, organization:, product:) }
  let(:filtered_card) { create(:rate_card, organization:, product:, product_filter:) }
  let(:other_product_card) { create(:rate_card, organization:) }

  describe "#fetch" do
    it "flags the cards whose slice the plan already prices, in one query" do
      catalog_plan = create(:catalog_plan, organization:)
      create(:plan_rate_card, organization:, catalog_plan:, rate_card: create(:rate_card, organization:, product:))
      source = described_class.new(organization, plan_id: catalog_plan.id)
      rate_cards = [default_card, filtered_card, other_product_card]

      result = nil
      statements = capture_sql { result = source.fetch(rate_cards) }

      expect(result).to eq([true, false, false])
      expect(statements.count { it.include?('FROM "plan_rate_cards"') }).to eq(1)
    end

    it "flags the cards whose slice the contract already prices" do
      contract = create(:contract, organization:, customer: create(:customer, organization:))
      create(:contract_rate_card, organization:, contract:, rate_card: create(:rate_card, organization:, product:, product_filter:))

      result = described_class.new(organization, contract_id: contract.id).fetch([default_card, filtered_card])

      expect(result).to eq([false, true])
    end

    it "flags no card for a plan outside the organization" do
      other_plan = create(:catalog_plan)
      create(:plan_rate_card, organization:, catalog_plan: other_plan, rate_card: create(:rate_card, organization:, product:))

      result = described_class.new(organization, plan_id: other_plan.id).fetch([default_card])

      expect(result).to eq([false])
    end

    # The customer portal reaches rate cards through invoice fees without a current organization.
    it "flags no card without an organization" do
      catalog_plan = create(:catalog_plan, organization:)
      create(:plan_rate_card, organization:, catalog_plan:, rate_card: create(:rate_card, organization:, product:))

      result = described_class.new(nil, plan_id: catalog_plan.id).fetch([default_card])

      expect(result).to eq([false])
    end
  end
end
