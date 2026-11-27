# frozen_string_literal: true

require "rails_helper"

describe "Billing timestamped contract units changes" do
  let(:organization) { create(:organization, webhook_url: nil, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR", invoice_grace_period: grace_period) }
  let(:product) { create(:product, :fixed, organization:) }
  let(:timing) { "arrears" }
  let(:proration) { true }
  let(:grace_period) { 0 }
  let(:rate_card) { create(:rate_card, organization:, product:, currency: "EUR", billing_timing: timing, proration:) }
  let(:contract) { create(:contract, :pending, organization:, customer:, started_at: Time.utc(2026, 9, 1)) }
  let(:contract_rate_card) do
    create(:contract_rate_card, organization:, contract:, rate_card:, units: 8,
      effective_date: Date.new(2026, 9, 1), billing_anchor_date: Date.new(2026, 9, 1))
  end
  let(:rate_model) { "standard" }
  let(:rate_properties) { {"amount" => "30"} }
  let(:future_rate) { nil }

  before do
    stub_pdf_generation
    create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 9, 1), rate_model:, rate_properties:)
    future_rate
    contract_rate_card
    travel_to(Time.utc(2026, 9, 1)) do
      perform_enqueued_jobs { Clock::ActivateContractsJob.perform_now }
    end
  end

  def change_units(units, at:, mode: "now", process: true)
    travel_to(at, with_usec: true) do
      perform_enqueued_jobs do
        put_with_token(organization, "/api/v2/contracts/#{contract.external_id}/applied_rate_cards/#{rate_card.code}",
          {applied_rate_card: {units:, apply_units: mode}})
        expect(response).to have_http_status(:success)
      end
    end
    bill_at(at + 1.minute) if process
  end

  def bill_at(timestamp)
    travel_to(timestamp) { perform_enqueued_jobs { Clock::ScheduleBillingOperationsJob.perform_now } }
  end

  it "weights an arrears decrease from the exact instant, including part of a day" do
    change_units(5, at: Time.utc(2026, 9, 16, 12))
    bill_at(Time.utc(2026, 10, 1))

    expect(customer.invoices.sole.total_amount_cents).to eq(19_650) # (8 × 15.5/30 + 5 × 14.5/30) × 3000.
    expect(customer.invoices.sole.fees.sole.amount_details["units_intervals"].size).to eq(2)
  end

  it "retains several changes on the same day" do
    change_units(5, at: Time.utc(2026, 9, 16, 6))
    change_units(8, at: Time.utc(2026, 9, 16, 18))
    bill_at(Time.utc(2026, 10, 1))

    expect(customer.invoices.sole.total_amount_cents).to eq(23_850) # (8 × 29.5/30 + 5 × 0.5/30) × 3000.
    expect(contract_rate_card.reload.units_changes.size).to eq(2)
    expect(contract_rate_card.terms.count).to eq(1)
  end

  it "retains exact arrears history when the clock processes several changes together" do
    first_change = Time.utc(2026, 9, 16, 6, 0, 0, 123456)
    second_change = Time.utc(2026, 9, 16, 18, 0, 0, 123456)
    change_units(5, at: first_change, process: false)
    change_units(8, at: second_change, process: false)

    expect(customer.invoices).to be_empty
    expect(contract_rate_card.billing_operations.pending.where(action_type: "reconcile_advance_coverage").count).to eq(2)
    bill_at(Time.utc(2026, 10, 1))

    expect(customer.invoices.sole.total_amount_cents).to eq(23_850) # 8 × 3000 minus 3 × 3000 × 0.5/30.
    expect(contract_rate_card.reload.units_changes.map { [it.billing_at, it.units_before, it.units_after] })
      .to eq([[first_change, 8, 5], [second_change, 5, 8]])
    expect(contract_rate_card.billing_operations.pending).to be_empty
    expect(contract_rate_card.next_billing_at).to eq(Time.utc(2026, 11, 1))
  end

  it "replaces an unbilled next-period change and leaves the current period untouched" do
    change_units(5, at: Time.utc(2026, 9, 10), mode: "next_billing_period")
    change_units(7, at: Time.utc(2026, 9, 20), mode: "next_billing_period")
    bill_at(Time.utc(2026, 10, 1))
    bill_at(Time.utc(2026, 11, 1))

    expect(customer.invoices.order(:created_at, :id).pluck(:total_amount_cents)).to eq([24_000, 21_000])
    expect(contract_rate_card.reload.terms.count).to eq(2)
  end

  it "preserves a scheduled change when units change immediately" do
    change_units(5, at: Time.utc(2026, 9, 10), mode: "next_billing_period", process: false)
    change_units(10, at: Time.utc(2026, 9, 20), process: false)
    bill_at(Time.utc(2026, 10, 1))
    bill_at(Time.utc(2026, 11, 1))

    expect(customer.invoices.order(:created_at, :id).pluck(:total_amount_cents)).to eq([26_200, 15_000])
    # September: (8 × 19/30 + 10 × 11/30) × 3000; October: scheduled 5 × 3000.
    expect(contract_rate_card.reload.terms.find_by!(effective_date: Date.new(2026, 9, 10)).units).to eq(5)
  end

  shared_examples "scheduled units at a new price boundary" do |expected_total|
    it "uses the scheduled quantity when a later rate adds an earlier boundary" do
      change_units(5, at: Time.utc(2026, 9, 10), mode: "next_billing_period")
      travel_to(Time.utc(2026, 9, 13)) do
        perform_enqueued_jobs do
          post_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}/rates",
            {rate: {code: "new_price", effective_from: "2026-09-20T00:00:00Z", rate_model: "standard",
                    billing_interval_unit: "month", rate_properties: {amount: "30"}}})
          expect(response).to have_http_status(:success)
        end
        get_with_token(organization, "/api/v2/contracts/#{contract.external_id}/applied_rate_cards/#{rate_card.code}")
        expect(response.parsed_body.fetch("applied_rate_card")).to include(
          "units" => "8.0", "scheduled_units" => "5.0", "scheduled_units_effective_at" => "2026-09-20T00:00:00.000000Z"
        )
      end
      bill_at(Time.utc(2026, 9, 20))
      bill_at(Time.utc(2026, 10, 1))

      expect(customer.invoices.sum(:total_amount_cents)).to eq(expected_total)
      expect(customer.invoices.joins(:fees).where(fees: {rate_card_rate_id: rate_card.rates.find_by!(code: "new_price").id})
        .flat_map(&:fees).map(&:units)).to eq([5])
      expect(contract_rate_card.reload.units_changes).to be_empty
    end
  end

  include_examples "scheduled units at a new price boundary", 20_700 # (8 × 19/30 + 5 × 11/30) × 3000.

  context "with graduated pricing" do
    let(:rate_model) { "graduated" }
    let(:rate_properties) do
      {"graduated_ranges" => [
        {"from_value" => 0, "to_value" => 5, "per_unit_amount" => "30", "flat_amount" => "0"},
        {"from_value" => 6, "to_value" => nil, "per_unit_amount" => "10", "flat_amount" => "0"}
      ]}
    end

    it "applies tiers once to the weighted units" do
      change_units(4, at: Time.utc(2026, 9, 16))
      bill_at(Time.utc(2026, 10, 1))

      expect(customer.invoices.sole.total_amount_cents).to eq(16_000) # Weighted units = (8 + 4)/2 = 6; 5 × 3000 + 1 × 1000.
    end
  end

  context "when paid in advance" do
    let(:timing) { "advance" }

    include_examples "scheduled units at a new price boundary", 29_500 # Original 24000 plus 5 × 3000 × 11/30.

    it "defers reconciliation to the clock and retains prepaid coverage across queued changes" do
      change_units(10, at: Time.utc(2026, 9, 10, 0, 0, 0, 123456), process: false)
      change_units(5, at: Time.utc(2026, 9, 20), process: false)
      change_units(10, at: Time.utc(2026, 9, 25), process: false)

      expect(customer.invoices.pluck(:total_amount_cents)).to eq([24_000])
      expect(contract_rate_card.billing_operations.pending.where(action_type: "reconcile_advance_coverage").count).to eq(3)
      bill_at(Time.utc(2026, 10, 1))
      bill_at(Time.utc(2026, 10, 1, 1))

      expect(customer.invoices.pluck(:total_amount_cents)).to match_array([24_000, 4_200, 30_000])
      # September increase: 2 × 3000 × (21 days minus 0.123456 seconds)/30 days; October: 10 × 3000.
      expect(customer.credit_notes).to be_empty
      expect(contract_rate_card.reload.units_changes.pluck(:units_after)).to eq([10, 5, 10])
    end

    context "with a rate change inside the period" do
      let(:future_rate) do
        create(:rate_card_rate, organization:, rate_card:, effective_from: Time.utc(2026, 9, 20),
          rate_properties: {"amount" => "60"})
      end

      it "prices additional units at each rate without charging the same coverage twice" do
        change_units(10, at: Time.utc(2026, 9, 10))

        expect(contract_rate_card.reload.next_billing_at).to eq(Time.utc(2026, 9, 20))
        bill_at(Time.utc(2026, 9, 20))
        bill_at(Time.utc(2026, 9, 20, 1))

        expect(customer.invoices.order(:created_at, :id).pluck(:total_amount_cents)).to eq([15_200, 2_000, 22_000])
        # First coverage: 8 × 3000 × 19/30; increase: 2 × 3000 × 10/30; later coverage: 10 × 6000 × 11/30.
        expect(contract_rate_card.billing_operations.find_by!(action_type: "reconcile_advance_coverage")
          .segments.sole.ended_at.iso8601(6)).to eq("2026-09-20T00:00:00.000000Z")
      end
    end

    it "does not charge again for 8 to 5 to 8" do
      original_cursor = contract_rate_card.reload.next_billing_at
      change_units(5, at: Time.utc(2026, 9, 10, 12))
      change_units(8, at: Time.utc(2026, 9, 20, 12))

      expect(customer.invoices.pluck(:total_amount_cents)).to eq([24_000])
      expect(customer.credit_notes).to be_empty
      expect(contract_rate_card.reload.next_billing_at).to eq(original_cursor)
      expect(contract_rate_card.billing_operations.where(action_type: "reconcile_advance_coverage").pending).to be_empty
    end

    it "keeps additional coverage after a later decrease" do
      change_units(10, at: Time.utc(2026, 9, 10))
      change_units(5, at: Time.utc(2026, 9, 20))
      change_units(10, at: Time.utc(2026, 9, 25))

      expect(customer.invoices.order(:created_at, :id).pluck(:total_amount_cents)).to eq([24_000, 4_200])
      # Additional coverage bought on September 10: 2 × 3000 × 21/30. It is still owned on September 25.
    end

    it "charges only additional prepaid coverage and uses the new units at renewal" do
      change_units(10, at: Time.utc(2026, 9, 16, 12))
      bill_at(Time.utc(2026, 10, 1))
      bill_at(Time.utc(2026, 10, 1, 1))

      expect(customer.invoices.order(:created_at, :id).pluck(:total_amount_cents)).to eq([24_000, 2_900, 30_000])
      # Top-up: (10 - 8) × 3000 × 14.5/30. Repeating the clock does not repeat it.
    end

    it "charges the decreased quantity next period without crediting the current period" do
      change_units(5, at: Time.utc(2026, 9, 16, 12))
      bill_at(Time.utc(2026, 10, 1))

      expect(customer.invoices.order(:created_at, :id).pluck(:total_amount_cents)).to eq([24_000, 15_000])
    end

    it "does not apply next-period changes early" do
      change_units(10, at: Time.utc(2026, 9, 16, 12), mode: "next_billing_period")
      expect(customer.invoices.pluck(:total_amount_cents)).to eq([24_000])

      bill_at(Time.utc(2026, 10, 1))
      expect(customer.invoices.order(:created_at, :id).pluck(:total_amount_cents)).to eq([24_000, 30_000])
    end

    it "keeps scheduled units after an immediate increase" do
      change_units(5, at: Time.utc(2026, 9, 10), mode: "next_billing_period", process: false)
      change_units(10, at: Time.utc(2026, 9, 20), process: false)
      bill_at(Time.utc(2026, 10, 1))

      expect(customer.invoices.pluck(:total_amount_cents)).to match_array([24_000, 2_200, 15_000])
      # September: 8 × 3000 plus 2 × 3000 × 11/30; October: scheduled 5 × 3000.
    end

    it "completes an unprocessed renewal before calculating the adjustment" do
      change_units(10, at: Time.utc(2026, 10, 1, 12))
      bill_at(Time.utc(2026, 10, 1, 13))

      expect(customer.invoices.order(:created_at, :id).pluck(:total_amount_cents)).to match_array([24_000, 24_000, 5_903])
      # October renewal: 8 × 3000; extra 2 seats: 2 × 3000 × 30.5/31, rounded once.
    end

    context "without proration" do
      let(:proration) { false }

      it "charges the full price only for the additional units" do
        change_units(10, at: Time.utc(2026, 9, 30, 12))

        expect(customer.invoices.order(:created_at, :id).pluck(:total_amount_cents)).to eq([24_000, 6_000]) # (10 - 8) × 3000.
      end
    end

    context "with an invoice grace period" do
      let(:grace_period) { 3 }

      it "retains exact adjustment boundaries when a draft is refreshed" do
        change_units(10, at: Time.utc(2026, 9, 16, 12, 0, 0, 123456))
        invoice = contract_rate_card.billing_operations.find_by!(action_type: "reconcile_advance_coverage").invoice
        properties = invoice.fees.sole.properties

        expect(properties.slice("from_datetime", "to_datetime")).to eq(
          "from_datetime" => "2026-09-16T12:00:00.123456Z",
          "to_datetime" => "2026-09-30T23:59:59.999999Z"
        )
        put_with_token(organization, "/api/v2/invoices/#{invoice.id}/refresh", {})

        expect(response).to have_http_status(:success)
        expect(invoice.reload.fees.sole.properties).to eq(properties)
        expect(invoice.total_amount_cents).to eq(2_900) # 2 × 3000 × (14.5 days minus 0.123456 seconds)/30 days, rounded once.
      end

      it "preserves the original renewal when its draft is refreshed after a decrease" do
        change_units(5, at: Time.utc(2026, 9, 2, 12))
        invoice = customer.invoices.sole

        expect(invoice).to be_draft
        put_with_token(organization, "/api/v2/invoices/#{invoice.id}/refresh", {})
        expect(response).to have_http_status(:success)
        expect(invoice.reload.total_amount_cents).to eq(24_000)
        expect(invoice.fees.sole.units).to eq(8)
      end
    end
  end
end
