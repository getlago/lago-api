# frozen_string_literal: true

require "rails_helper"

describe "Previewing and billing a monthly card whose price changes every day" do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:contract_path) { "/api/v2/contracts/seats-contract" }
  let(:days) { (Date.new(2027, 2, 1)..Date.new(2027, 2, 28)).to_a }
  let(:rates) do
    days.map do |date|
      {code: "price-#{date.day}", effective_from: date.iso8601, rate_model: "standard",
       billing_interval_unit: "month", rate_properties: {amount: date.day.to_s}}
    end
  end

  around do |example|
    travel_to(Time.utc(2027, 1, 31))
    example.run
  ensure
    travel_back
  end

  before do
    create_or_update_customer({external_id: "seat-holder", timezone: "UTC", currency: "EUR"})
    api_call do
      post_with_token(organization, "/api/v2/products", {product: {name: "Seats", code: "seats", product_type: "fixed"}})
    end
    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: "Monthly seats", code: "monthly-seats", product_code: "seats", currency: "EUR",
        billing_timing: "arrears", proration: true, rates:
      }})
    end
    api_call do
      post_with_token(organization, "/api/v2/contracts", {contract: {
        external_id: "seats-contract", external_customer_id: "seat-holder", started_at: "2027-02-01T00:00:00Z"
      }})
    end
    api_call do
      post_with_token(organization, "#{contract_path}/applied_rate_cards", {applied_rate_card: {
        rate_card_code: "monthly-seats", units: 28, billing_scope:
      }})
    end
    travel_to(Time.utc(2027, 2, 1, 0, 5))
    perform_enqueued_jobs { Clock::ActivateContractsJob.perform_now }
  end

  def preview
    api_call do
      get_with_token(organization, "#{contract_path}/operations", {start_on: days.first.iso8601, end_on: days.last.iso8601})
    end
  end

  def bill(date)
    travel_to(date.to_time(:utc).noon)
    api_call { post_with_token(organization, "#{contract_path}/bill", {end_on: date.iso8601}) }.fetch(:invoices)
  end

  shared_examples "bills each daily price exactly once" do
    it "matches every previewed day and obligation to its finalized fee and invoice" do
      original = preview
      obligations = original.fetch(:billing_obligations)
      due_dates = groups.map { |dates| dates.last.next_day }
      expect(obligations.pluck(:billing_at)).to eq(due_dates.map { it.to_time(:utc).iso8601(6) })
      expect(obligations.pluck(:billing_scope).uniq).to eq([billing_scope])
      expect(obligations.pluck(:cycle_index).uniq).to eq([1])
      expect(original[:next_billing_at]).to eq("2027-03-01T00:00:00.000000Z")

      obligations.zip(groups).each do |obligation, dates|
        expect(obligation[:segments].map { it.values_at(:period_from, :period_to, :rate_code, :properties, :proration_ratio) }).to eq(
          dates.map do |date|
            [date.to_time(:utc).iso8601(6), date.to_time(:utc).end_of_day.iso8601(6),
              "price-#{date.day}", {"amount" => date.day.to_s}, 1.fdiv(28)]
          end
        )
      end

      midmonth = Date.new(2027, 2, 15)
      first_invoices = bill(midmonth)
      expect(first_invoices.pluck(:issuing_date)).to eq(due_dates.select { it <= midmonth }.map(&:iso8601))
      close = Date.new(2027, 3, 1)
      invoices = first_invoices + bill(close)
      expect(invoices.pluck(:issuing_date)).to eq(due_dates.map(&:iso8601))

      invoices.zip(groups, obligations).each do |invoice, dates, obligation|
        # 28 seats × EUR day-of-month per seat × 1/28 of the monthly cycle.
        cents = dates.map { it.day * 100 }
        expect(invoice).to include(status: "finalized", currency: "EUR", total_amount_cents: cents.sum)
        expect(invoice[:fees].pluck(:amount_cents)).to match_array(cents)
        stored = organization.invoices.find(invoice[:lago_id])
        expect(stored.billing_operations.completed.sole.billing_at.iso8601(6)).to eq(obligation[:billing_at])
        fees = stored.fees.sort_by { it.properties.fetch("from_datetime") }
        expect(fees.map { [it.rate_card_rate_id, it.amount_cents, it.properties.values_at("from_datetime", "to_datetime")] }).to eq(
          obligation[:segments].zip(cents).map { |segment, amount| [segment[:lago_rate_id], amount, segment.values_at(:period_from, :period_to)] }
        )
      end
      expect(invoices.sum { it[:total_amount_cents] }).to eq(40_600) # EUR (1 + 28) × 28 / 2
      expect(bill(close)).to be_empty
      expect(preview).to eq(original)
    end
  end

  context "with cycle scope" do
    let(:billing_scope) { "cycle" }
    let(:groups) { [days] }

    include_examples "bills each daily price exactly once"
  end

  context "with segment scope" do
    let(:billing_scope) { "segment" }
    let(:groups) { days.map { [it] } }

    include_examples "bills each daily price exactly once"
  end
end
