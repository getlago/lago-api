# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingCycles::RefreshService do
  subject(:result) { described_class.call(contract_rate_card:) }

  let(:contract_rate_card) do
    create(:contract_rate_card, contract:, organization: contract.organization,
      effective_date: Date.new(2026, 1, 15), billing_anchor_date: Date.new(2026, 1, 1))
  end
  let!(:phase) { create(:rate_phase, :contract_level, contract_rate_card:, organization: contract.organization) }
  let(:contract) { create(:contract, status: :pending, started_at: Time.utc(2026, 1, 15)) }

  before do
    create(:rate_card_rate, rate_card: contract_rate_card.rate_card, organization: contract.organization,
      effective_from: Time.utc(2026, 1, 1))
  end

  around { |example| travel_to(Time.utc(2026, 1, 10)) { example.run } }

  it "creates the first full period before the contract starts" do
    expect(result).to be_success
    expect(result.billing_cycle).to have_attributes(
      cycle_index: 0, started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 2, 1)
    )
    expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 2, 1))
    expect(contract_rate_card.billing_segments).to be_empty
  end

  context "with an existing first cycle" do
    let!(:existing) do
      create(:billing_cycle, contract_rate_card:, organization: contract.organization)
    end

    it "keeps the record unchanged when the calendar is unchanged" do
      expect { result }.not_to change { existing.reload.attributes }
      expect(result.billing_cycle).to eq(existing)
    end

    context "when a phase override changes the cadence" do
      subject(:result) do
        RatePhases::UpdateService.call(rate_phase: phase,
          params: {rate_override: {rate_model: "standard", rate_properties: {amount: "10"}, billing_interval_count: 1, billing_interval_unit: "week"}})
      end

      it "refreshes the same cycle and brings the billing clock forward" do
        expect(result).to be_success
        expect(existing.reload).to have_attributes(started_at: Time.utc(2026, 1, 15), ended_at: Time.utc(2026, 1, 22))
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 1, 22))
      end
    end

    context "when a phase override only changes the price" do
      subject(:result) do
        RatePhases::UpdateService.call(rate_phase: phase, params: {rate_override: {rate_model: "standard", rate_properties: {amount: "25"}}})
      end

      it "preserves the cycle's identity and boundaries" do
        expect { result }.not_to change { existing.reload.attributes }
        expect(result).to be_success
      end
    end

    context "when a weekly intro phase is inserted" do
      subject(:result) do
        RatePhases::CreateService.call(contract_rate_card:, params: {code: "intro", position: 1,
                                                                     billing_interval_cycle_count: 2, rate_override: {rate_model: "standard", rate_properties: {amount: "10"}, billing_interval_count: 1, billing_interval_unit: "week"}})
      end

      it "refreshes the first period from the new phase" do
        expect(result).to be_success
        expect(existing.reload.ended_at).to eq(Time.utc(2026, 1, 22))
      end
    end

    context "when the phase sequence is replaced" do
      subject(:result) do
        RatePhases::ReplaceService.call(contract_rate_card:, phases_params: [
          {code: "weekly", position: 1, rate_override: {rate_model: "standard", rate_properties: {amount: "10"}, billing_interval_count: 1, billing_interval_unit: "week"}}
        ])
      end

      it "refreshes the first period after replacing the entire sequence" do
        expect(result).to be_success
        expect(existing.reload.ended_at).to eq(Time.utc(2026, 1, 22))
      end
    end

    context "when the intro phase is removed" do
      subject(:result) { RatePhases::DestroyService.call(rate_phase: intro) }

      let!(:intro) do
        create(:rate_phase, :contract_level, contract_rate_card:, organization: contract.organization,
          position: 1, billing_interval_cycle_count: 2, rate_override: override)
      end
      let(:override) do
        create(:rate_override, organization: contract.organization, billing_interval_count: 1, billing_interval_unit: "week")
      end
      let!(:phase) { create(:rate_phase, :contract_level, contract_rate_card:, organization: contract.organization, position: 2) }
      let!(:existing) do
        create(:billing_cycle, contract_rate_card:, organization: contract.organization,
          started_at: Time.utc(2026, 1, 15), ended_at: Time.utc(2026, 1, 22))
      end

      it "restores the base cadence" do
        expect(result).to be_success
        expect(existing.reload).to have_attributes(started_at: Time.utc(2026, 1, 1), ended_at: Time.utc(2026, 2, 1))
      end
    end

    context "when the card's anchor is edited" do
      subject(:result) do
        ContractRateCards::UpdateService.call(contract_rate_card:, params: {billing_anchor_date: "2026-01-15"})
      end

      it "refreshes the cycle and the clock in the same transaction" do
        expect(result).to be_success
        expect(existing.reload).to have_attributes(started_at: Time.utc(2026, 1, 15), ended_at: Time.utc(2026, 2, 15))
        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 2, 15))
      end
    end

    context "when the contract is active" do
      let(:contract) { create(:contract, status: :active, started_at: Time.utc(2026, 1, 15)) }

      it "does not rewrite a signed calendar" do
        expect { result }.not_to change { existing.reload.attributes }
        expect(result.error.messages).to eq(contract: ["contract_locked"])
      end
    end
  end
end
