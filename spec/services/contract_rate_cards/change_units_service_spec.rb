# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::ChangeUnitsService do
  subject(:result) { described_class.call(contract_rate_card:, params:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:, timezone: "UTC") }
  let(:contract) { create(:contract, organization:, customer:, started_at: Time.utc(2026, 9, 1)) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:rate_card) { create(:rate_card, organization:, product:) }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, units: 8,
      effective_date: Date.new(2026, 9, 1), billing_anchor_date: Date.new(2026, 9, 1))
  end
  let(:params) { {units: "5", apply_units: "now"} }
  let(:timestamp) { Time.utc(2026, 9, 15, 12, 30, 0, 123456) }

  around { |example| travel_to(timestamp, with_usec: true) { example.run } }

  before do
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 9, 1))
  end

  it "preserves the original quantity and records the exact change time" do
    expect(result).to be_success
    expect(contract_rate_card.reload.terms.map { [it.units, it.effective_at] }).to eq([[8, nil], [5, timestamp]])
    expect(contract_rate_card.terms.first.effective_date).to eq(Date.new(2026, 9, 1))
  end

  context "when applying to the next billing period" do
    let(:params) { {units: "5", apply_units: "next_billing_period"} }

    it "records the cycle boundary without enqueuing an immediate adjustment" do
      expect { result }.not_to have_enqueued_job(BillingOperations::ProcessJob)
      expect(result).to be_success
      expect(contract_rate_card.terms.find_by(effective_at: Time.utc(2026, 10, 1))).to have_attributes(units: 5, application_timing: "next_billing_cycle")
    end
  end

  context "with an invalid mode" do
    let(:params) { {units: "5", apply_units: "later"} }

    it "rejects it without writing units" do
      contract_rate_card
      expect { result }.not_to change(ContractRateCardTerm, :count)
      expect(result.error.messages[:apply_units]).to eq(["value_is_invalid"])
    end
  end

  context "with invalid units" do
    let(:params) { {units: "-1", apply_units: "now"} }

    it "preserves all history on validation failure" do
      contract_rate_card
      expect { result }.not_to change(ContractRateCardTerm, :count)
      expect(result.error.messages[:units]).to be_present
    end
  end

  context "with missing units" do
    let(:params) { {apply_units: "now"} }

    it "returns a validation failure" do
      expect(result.error.messages[:units]).to eq(["value_is_mandatory"])
    end
  end

  context "with a structural edit" do
    let(:params) { {units: "5", apply_units: "now", billing_anchor_date: "2026-09-02"} }

    it "keeps active pricing configuration locked" do
      expect(result.error.messages[:contract]).to eq(["contract_locked"])
    end
  end

  context "with a terminated contract" do
    let(:contract) { create(:contract, :terminated, organization:, customer:, started_at: Time.utc(2026, 9, 1)) }

    it "rejects the change" do
      expect(result.error.messages[:contract]).to eq(["contract_locked"])
    end
  end

  context "when the existing units change has already been billed" do
    before do
      create(:contract_rate_card_term, organization:, contract_rate_card:, units: 10, effective_date: nil, effective_at: timestamp)
      create(:billing_operation, organization:, customer:, contract_rate_card:, billing_at: timestamp, processed_at: timestamp)
    end

    it "preserves the billed quantity without sending an update webhook" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result.error.messages[:units]).to eq(["units_already_billed"])
      expect(result.contract_rate_card).to be_nil
      expect(contract_rate_card.reload.terms.find_by(effective_at: timestamp).units).to eq(10)
    end
  end
end
