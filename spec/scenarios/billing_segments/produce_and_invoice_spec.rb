# frozen_string_literal: true

require "rails_helper"

# The clocks discover due operations and invoice them through the real calendar and fee computation.
describe "Billing operations discovered by the clocks and invoiced" do
  let(:organization) { create(:organization, webhook_url: nil, feature_flags: ["product_catalog"]) }
  let(:customer) { create(:customer, organization:, timezone: "UTC", currency: "EUR") }
  let(:product) { create(:product, :fixed, organization:) }
  let(:billing_scope) { "cycle" }
  let(:proration) { false }
  let(:initial_amount) { "50" }

  let(:rate_card) do
    create(:rate_card, organization:, product:, currency: "EUR", billing_timing: "arrears", proration:)
  end

  let(:contract) do
    create(:contract, :pending, organization:, customer:, billing_entity: organization.default_billing_entity,
      started_at: Time.zone.parse("2026-01-01 00:00:00"))
  end

  before do
    stub_pdf_generation

    create(:rate_card_rate, organization:, rate_card:,
      effective_from: Time.zone.parse("2026-01-01 00:00:00"),
      rate_model: "standard", rate_properties: {"amount" => initial_amount},
      billing_interval_count: 1, billing_interval_unit: "month")

    create(:contract_rate_card, organization:, contract:, rate_card:, units: 3, billing_scope:,
      effective_date: Date.new(2026, 1, 1), billing_anchor_date: Date.new(2026, 1, 1))

    travel_to(Time.zone.parse("2026-01-01 00:05:00")) do
      perform_enqueued_jobs { Clock::ActivateContractsJob.perform_now }
    end
  end

  def run_billing_clocks
    perform_enqueued_jobs do
      Clock::ScheduleBillingOperationsJob.perform_now
    end
  end

  it "bills January in arrears on the tick that follows it" do
    travel_to(Time.zone.parse("2026-02-01 00:12:00")) do
      run_billing_clocks
    end

    invoice = Invoice.where(customer:).sole

    expect(invoice).to have_attributes(status: "finalized", currency: "EUR", total_amount_cents: 15_000)
    expect(invoice.billing_operations.sole).to have_attributes(
      target_cycle_started_at: Time.zone.parse("2026-01-01 00:00:00"),
      billing_at: Time.zone.parse("2026-02-01 00:00:00"),
      processed_at: Time.zone.parse("2026-02-01 00:12:00"),
      invoice_id: invoice.id
    )
    expect(LegacyBillingSegment.where(customer_id: customer.id)).to be_empty
  end

  it "moves the clock on, so the next tick bills February and not January again" do
    travel_to(Time.zone.parse("2026-02-01 00:12:00")) do
      run_billing_clocks
    end

    expect(ContractRateCard.sole.next_billing_at).to eq(Time.zone.parse("2026-03-01 00:00:00"))

    travel_to(Time.zone.parse("2026-03-01 00:12:00")) do
      run_billing_clocks
    end

    expect(BillingOperation.where(customer:).where.not(processed_at: nil)
      .order(:target_cycle_started_at).pluck(:target_cycle_started_at)).to eq(
      [Time.zone.parse("2026-01-01 00:00:00"), Time.zone.parse("2026-02-01 00:00:00")]
    )
  end

  context "when a rate changes during the cycle" do
    let(:proration) { true }
    let(:initial_amount) { "62" }
    let(:cycle_start) { Time.zone.parse("2026-01-01 00:00:00") }
    let(:rate_change) { Time.zone.parse("2026-01-15 00:00:00") }
    let(:cycle_end) { Time.zone.parse("2026-02-01 00:00:00") }
    let(:card) { ContractRateCard.find_by!(contract:, rate_card:) }
    let(:first_rate) { rate_card.rates.order(:effective_from).first }
    let(:second_rate) { rate_card.rates.find_by!(code: "new-price") }

    before do
      travel_to(Time.zone.parse("2026-01-05 00:00:00")) do
        api_call do
          post_with_token(organization, "/api/v2/rate_cards/#{rate_card.code}/rates", {rate: {
            code: "new-price", effective_from: rate_change.iso8601, rate_model: "standard",
            billing_interval_unit: "month", rate_properties: {amount: "31"}
          }})
        end
      end
    end

    def expect_fee(fee, rate, amount, from, to)
      expect(fee).to have_attributes(rate_card_rate_id: rate.id, contract_rate_card_id: card.id, amount_cents: amount, units: 3)
      expect(fee.properties).to include(
        "from_datetime" => from.iso8601(6),
        "to_datetime" => BillingSegment.inclusive_end(to).iso8601(6)
      )
    end

    it "waits for cycle close and invoices both price segments once" do
      travel_to(rate_change + 12.minutes) { run_billing_clocks }

      expect(Invoice.where(customer:)).to be_empty
      expect(card.reload.next_billing_at).to eq(cycle_end)

      travel_to(cycle_end + 12.minutes) do
        run_billing_clocks
        run_billing_clocks
      end

      invoice = Invoice.where(customer:).sole
      operation = invoice.billing_operations.sole
      expect(invoice).to have_attributes(status: "finalized", total_amount_cents: 13_500)
      expect(operation).to have_attributes(
        contract_rate_card_id: card.id, action_type: "close_fixed_arrears",
        target_cycle_started_at: cycle_start, billing_at: cycle_end,
        processed_at: cycle_end + 12.minutes, invoice_id: invoice.id
      )
      expect(BillingOperation.where(customer:).completed.pluck(:id)).to eq([operation.id])
      expect(card.reload.next_billing_at).to eq(Time.zone.parse("2026-03-01"))
      fees = invoice.fees.order(Arel.sql("properties->>'from_datetime'")).to_a
      expect(fees.size).to eq(2)
      expect_fee(fees[0], first_rate, 8_400, cycle_start, rate_change) # 3 units * 6,200 cents * 14 / 31 days
      expect_fee(fees[1], second_rate, 5_100, rate_change, cycle_end) # 3 units * 3,100 cents * 17 / 31 days
    end

    context "with segment billing" do
      let(:billing_scope) { "segment" }

      it "invoices each price segment at its own boundary once" do
        travel_to(rate_change + 12.minutes) do
          run_billing_clocks
          run_billing_clocks
        end

        first_invoice = Invoice.where(customer:).sole
        first_operation = first_invoice.billing_operations.sole
        expect(first_invoice).to have_attributes(status: "finalized", total_amount_cents: 8_400)
        expect(first_operation).to have_attributes(
          contract_rate_card_id: card.id, action_type: "close_fixed_arrears",
          target_cycle_started_at: cycle_start, billing_at: rate_change,
          processed_at: rate_change + 12.minutes, invoice_id: first_invoice.id
        )
        expect_fee(first_invoice.fees.sole, first_rate, 8_400, cycle_start, rate_change) # 3 * 6,200 * 14 / 31
        expect(card.reload.next_billing_at).to eq(cycle_end)

        travel_to(cycle_end + 12.minutes) do
          run_billing_clocks
          run_billing_clocks
        end

        second_invoice = Invoice.where(customer:).where.not(id: first_invoice.id).sole
        second_operation = second_invoice.billing_operations.sole
        expect(second_invoice).to have_attributes(status: "finalized", total_amount_cents: 5_100)
        expect(second_operation).to have_attributes(
          contract_rate_card_id: card.id, action_type: "close_fixed_arrears",
          target_cycle_started_at: cycle_start, billing_at: cycle_end,
          processed_at: cycle_end + 12.minutes, invoice_id: second_invoice.id
        )
        expect_fee(second_invoice.fees.sole, second_rate, 5_100, rate_change, cycle_end) # 3 * 3,100 * 17 / 31
        expect(BillingOperation.where(customer:).completed.order(:billing_at).pluck(:id)).to eq([first_operation.id, second_operation.id])
        expect(card.reload.next_billing_at).to eq(Time.zone.parse("2026-03-01"))
      end
    end
  end
end
