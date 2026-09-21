# frozen_string_literal: true

require "rails_helper"

RSpec.describe Sources::ContractResolvedRatePhases do
  subject(:source) { described_class.new }

  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:) }
  let(:catalog_plan) { create(:catalog_plan, organization:) }
  let(:plan_rate_card) { create(:plan_rate_card, organization:, catalog_plan:, rate_card:) }
  let(:materialized_card) { create(:contract_rate_card, organization:, contract: create(:contract, organization:, catalog_plan:), rate_card:) }
  let(:authored_card) { create(:contract_rate_card, organization:, contract: create(:contract, organization:, catalog_plan:), rate_card:) }
  let(:plan_less_card) { create(:contract_rate_card, organization:, contract: create(:contract, organization:, catalog_plan: nil), rate_card:) }
  let!(:plan_phase) { create(:rate_phase, organization:, plan_rate_card:, code: "default", position: 1) }
  let!(:own_phase) { create(:rate_phase, :contract_level, organization:, contract_rate_card: authored_card, code: "custom", position: 1) }

  describe "#fetch" do
    it "returns each card's own phases when present, else its plan entry's" do
      expect(source.fetch([materialized_card, authored_card])).to eq([[plan_phase], [own_phase]])
    end

    it "returns none for a card on a plan-less contract" do
      expect(source.fetch([plan_less_card])).to eq([[]])
    end
  end
end
