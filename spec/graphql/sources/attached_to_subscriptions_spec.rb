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

    context "when the only contracts are canceled" do
      let(:canceled_plan) { create(:catalog_plan, organization:) }
      let(:direct) { create(:rate_card, organization:, product:) }
      let(:through_plan) { create(:rate_card, organization:, product:) }

      before do
        canceled_contract = create(:contract, :canceled, organization:, customer: create(:customer, organization:), catalog_plan: canceled_plan)
        create(:contract_rate_card, organization:, contract: canceled_contract, rate_card: direct)
        create(:plan_rate_card, organization:, catalog_plan: canceled_plan, rate_card: through_plan)
      end

      it "ignores them, as RateCard#attached_to_subscriptions? does" do
        expect(source.fetch([direct.id, through_plan.id])).to eq([false, false])
        expect([direct, through_plan].map(&:attached_to_subscriptions?)).to eq([false, false])
      end
    end
  end
end
