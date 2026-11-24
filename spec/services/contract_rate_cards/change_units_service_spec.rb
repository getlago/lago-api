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
    expect { result }.not_to have_enqueued_job(BillingOperations::ProcessJob)
    expect(result).to be_success
    expect(contract_rate_card.reload.units_changes.sole).to have_attributes(billing_at: timestamp, units_before: 8, units_after: 5, processed_at: nil)
    expect(contract_rate_card.terms.sole.units).to eq(8)
    expect(contract_rate_card.terms.first.effective_date).to eq(Date.new(2026, 9, 1))
  end

  context "when applying to the next billing period" do
    let(:params) { {units: "5", apply_units: "next_billing_period"} }

    it "records the cycle boundary without enqueuing an immediate adjustment" do
      expect { result }.not_to have_enqueued_job(BillingOperations::ProcessJob)
      expect(result).to be_success
      expect(contract_rate_card.terms.find_by(effective_date: Date.new(2026, 10, 1))).to have_attributes(units: 5, application_timing: "next_billing_cycle")
      expect(contract_rate_card.units_changes).to be_empty
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
      expect { result }.not_to change { [ContractRateCardTerm.count, BillingOperation.count] }
      expect(result.error.messages[:units]).to be_present
      expect(result.error.messages).not_to have_key(:units_after)
      expect(result.error.meta[:units]).to eq(min: 0)
    end

    context "when the value is not numeric" do
      let(:params) { {units: "invalid", apply_units: "now"} }

      it "returns a validation failure without recording a change" do
        expect(result.error.messages[:units]).to be_present
        expect(contract_rate_card.units_changes).to be_empty
      end
    end
  end

  context "when paid in advance" do
    let(:rate_card) { create(:rate_card, :advance, organization:, product:) }

    it "persists reconciliation without enqueueing billing directly" do
      expect { result }.not_to have_enqueued_job(BillingOperations::ProcessJob)
      expect(result).to be_success
      expect(contract_rate_card.reload.units_changes.sole).to have_attributes(units_before: 8, units_after: 5, processed_at: nil)
      expect(customer.invoices).to be_empty
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
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "reconcile_units",
        billing_at: timestamp, processed_at: timestamp, units_before: 8, units_after: 10)
    end

    it "preserves the billed quantity without sending an update webhook" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result.error.messages[:units]).to eq(["units_already_billed"])
      expect(result.contract_rate_card).to be_nil
      expect(contract_rate_card.reload.units_changes.sole.units_after).to eq(10)
    end
  end

  context "when a change is already pending at the same exact instant" do
    before do
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "reconcile_units",
        billing_at: timestamp, units_before: 8, units_after: 10)
    end

    it "preserves the earlier record and returns a validation failure" do
      expect { result }.not_to have_enqueued_job(SendWebhookJob)
      expect(result.error.messages[:units]).to eq(["value_already_exist"])
      expect(contract_rate_card.reload.units_changes.sole.units_after).to eq(10)
    end
  end

  context "when the contract has no next billing period" do
    let(:params) { {units: "5", apply_units: "next_billing_period"} }
    let(:contract) do
      create(:contract, organization:, customer:, started_at: Time.utc(2026, 9, 1), ended_at: Time.utc(2026, 9, 20, 12))
    end

    it "does not move a termination time to the beginning of that day" do
      expect(result.error.messages[:contract]).to eq(["contract_locked"])
      expect(contract_rate_card.reload.terms.sole.units).to eq(8)
      expect(contract_rate_card.units_changes).to be_empty
    end
  end
end
