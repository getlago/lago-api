# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCards::ChangeUnitsService do
  subject(:result) { described_class.call(contract_rate_card:, params:) }

  let(:organization) { create(:organization) }
  let(:rate_effective_from) { Time.utc(2026, 9, 1) }
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
    create(:rate_card_rate, organization:, rate_card:, effective_from: rate_effective_from)
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

    it "records the request date without enqueuing an immediate adjustment" do
      expect { result }.not_to have_enqueued_job(BillingOperations::ProcessJob)
      expect(result).to be_success
      expect(contract_rate_card.terms.find_by(effective_date: Date.new(2026, 9, 15))).to have_attributes(units: 5, application_timing: "next_billing_cycle")
      expect(contract_rate_card.units_changes).to be_empty
    end
  end

  context "when scheduling on the card's first day" do
    let(:timestamp) { Time.utc(2026, 9, 1, 12) }
    let(:params) { {units: "5", apply_units: "next_billing_period"} }

    it "keeps the starting quantity and the scheduled quantity on the same date" do
      expect(result).to be_success
      expect(contract_rate_card.reload.terms.count).to eq(2)
      expect(ContractRateCards::UnitsAtService.call!(contract_rate_card:, timestamp:).units).to eq(8)
      expect(contract_rate_card.terms.find_by!(application_timing: :next_billing_cycle).effective_date).to eq(Date.new(2026, 9, 1))
    end
  end

  context "when the request is on the previous day in the customer timezone" do
    let(:customer) { create(:customer, organization:, timezone: "America/New_York") }
    let(:timestamp) { Time.utc(2026, 9, 15, 2) }
    let(:params) { {units: "5", apply_units: "next_billing_period"} }

    it "stores the customer's request date and resolves the next local boundary" do
      expect(result).to be_success
      expect(contract_rate_card.terms.find_by!(application_timing: :next_billing_cycle).effective_date).to eq(Date.new(2026, 9, 14))
      expect(ContractRateCards::UnitsAtService.call!(contract_rate_card:, timestamp:).scheduled_term.starts_at).to eq(Time.utc(2026, 10, 1, 4))
    end
  end

  context "when the first price is not effective yet" do
    let(:rate_effective_from) { Time.utc(2026, 9, 20) }

    before { contract_rate_card }

    it "returns a validation failure without changing units or creating billing work" do
      expect { result }.not_to change { [ContractRateCardTerm.count, BillingOperation.count] }
      expect(result).to be_failure
      expect(result.error.messages[:units]).to eq(["no_effective_rate"])
      expect(contract_rate_card.reload.terms.sole.units).to eq(8)
      expect(SendWebhookJob).not_to have_been_enqueued
    end

    context "when paid in advance" do
      let(:rate_card) { create(:rate_card, :advance, organization:, product:) }

      it "returns the same validation error" do
        expect(result).to be_failure
        expect(result.error.messages[:units]).to eq(["no_effective_rate"])
        expect(contract_rate_card.units_changes).to be_empty
      end
    end

    context "when applying at the next billing period" do
      let(:params) { {units: "5", apply_units: "next_billing_period"} }

      it "preserves the ability to schedule units for a later priced period" do
        expect(result).to be_success
        expect(contract_rate_card.terms.find_by!(effective_date: Date.new(2026, 9, 15)).units).to eq(5)
      end
    end
  end

  context "when a price is added after units were scheduled" do
    let(:params) { {units: "5", apply_units: "next_billing_period"} }

    it "applies the scheduled quantity at the new price boundary" do
      expect(result).to be_success
      expect(ContractRateCards::UnitsAtService.call!(contract_rate_card:, timestamp:).scheduled_term.starts_at).to eq(Time.utc(2026, 10, 1))
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 9, 20))
      contract_rate_card.reload

      expect(ContractRateCards::UnitsAtService.call!(contract_rate_card:, timestamp:).scheduled_term.starts_at).to eq(Time.utc(2026, 9, 20))
      expect(ContractRateCards::UnitsAtService.call!(contract_rate_card:, timestamp: Time.utc(2026, 9, 19)).units).to eq(8)
      expect(ContractRateCards::UnitsAtService.call!(contract_rate_card:, timestamp: Time.utc(2026, 9, 20)).units).to eq(5)
    end
  end

  context "when replacing pending scheduled units with invalid units" do
    let(:params) { {units: "-1", apply_units: "next_billing_period"} }

    before do
      described_class.call!(contract_rate_card:, params: {units: "7", apply_units: "next_billing_period"})
    end

    it "keeps the earlier scheduled quantity" do
      expect(result).to be_failure
      expect(contract_rate_card.reload.terms.find_by!(application_timing: :next_billing_cycle).units).to eq(7)
    end
  end

  context "when another scheduled change is requested on the same date" do
    let(:rate_card) { create(:rate_card, :advance, organization:, product:) }

    before { create(:rate_card_rate, organization:, rate_card:, effective_from: timestamp + 1.hour) }

    it "replaces the pending change and skips the same-day price boundary" do
      described_class.call!(contract_rate_card:, params: {units: "5", apply_units: "next_billing_period"})
      travel_to(timestamp + 2.hours, with_usec: true)
      described_class.call!(contract_rate_card:, params: {units: "7", apply_units: "next_billing_period"})
      history = ContractRateCards::UnitsAtService.call!(contract_rate_card:, timestamp: Time.current)
      expect(history.units).to eq(8)
      expect(history.scheduled_term).to have_attributes(units: 7, starts_at: Time.utc(2026, 10, 1))
      expect(contract_rate_card.reload.terms.where(application_timing: :next_billing_cycle).count).to eq(1)
    end
  end

  context "when the next UTC date is still the request date for the customer" do
    let(:customer) { create(:customer, organization:, timezone: "America/New_York") }
    let(:rate_card) { create(:rate_card, :advance, organization:, product:) }
    let(:timestamp) { Time.utc(2026, 9, 15, 2) }
    let(:params) { {units: "5", apply_units: "next_billing_period"} }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 9, 15, 3))
      create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 9, 15, 4))
    end

    it "skips the same local date and includes midnight on the following date" do
      expect(result).to be_success
      history = ContractRateCards::UnitsAtService.call!(contract_rate_card:, timestamp:)
      expect(history.scheduled_term.starts_at).to eq(Time.utc(2026, 9, 15, 4))
      expect(ContractRateCards::UnitsAtService.call!(contract_rate_card:, timestamp: Time.utc(2026, 9, 15, 3)).units).to eq(8)
      expect(ContractRateCards::UnitsAtService.call!(contract_rate_card:, timestamp: Time.utc(2026, 9, 15, 4)).units).to eq(5)
    end
  end

  context "when the only remaining price boundary is on the request date" do
    let(:rate_card) { create(:rate_card, :advance, organization:, product:) }
    let(:contract) do
      create(:contract, organization:, customer:, started_at: Time.utc(2026, 9, 1), ended_at: timestamp + 1.day)
    end
    let(:params) { {units: "5", apply_units: "next_billing_period"} }

    before do
      create(:rate_card_rate, organization:, rate_card:, effective_from: timestamp + 1.hour)
    end

    it "returns a validation error without scheduling a change" do
      expect(result).to be_failure
      expect(result.error.messages[:contract]).to eq(["contract_locked"])
      expect(contract_rate_card.reload.terms.sole.units).to eq(8)
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
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "reconcile_advance_coverage",
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
      create(:billing_operation, organization:, customer:, contract_rate_card:, action_type: "reconcile_advance_coverage",
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
