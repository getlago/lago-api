# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sources::AttachedToSubscriptions do
  subject(:source) { described_class.new }

  let(:organization) { create(:organization) }
  let(:product) { create(:product, organization:) }

  describe "#fetch" do
    it "flags cards billed directly or through a plan that has contracts" do
      direct = create(:rate_card, organization:, product:)
      create(:contract_rate_card, organization:, rate_card: direct)

      through_contracted_plan = create(:rate_card, organization:, product:)
      contracted_plan = create(:catalog_plan, organization:)
      create(:plan_rate_card, organization:, catalog_plan: contracted_plan, rate_card: through_contracted_plan)
      create(:contract, organization:, catalog_plan: contracted_plan)

      plan_without_contract = create(:rate_card, organization:, product:)
      create(:plan_rate_card, organization:, rate_card: plan_without_contract)

      result = source.fetch([direct.id, through_contracted_plan.id, plan_without_contract.id])

      expect(result).to eq([true, true, false])
    end
  end
end
