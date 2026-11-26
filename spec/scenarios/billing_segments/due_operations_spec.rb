# frozen_string_literal: true

require "rails_helper"

describe "Daily contract billing after a scheduling outage" do
  let(:organization) { create(:organization, feature_flags: ["product_catalog"], webhook_url: nil) }
  let(:customer) { organization.customers.find_by!(external_id: "daily-customer") }
  let(:contract) { organization.contracts.find_by!(external_id: "daily-contract") }
  let(:card) { contract.applied_rate_cards.sole }
  let(:started_at) { Time.utc(2026, 10, 31) }
  let(:first_tick) { Time.utc(2026, 11, 1, 0, 5) }
  let(:catchup_tick) { Time.utc(2026, 11, 19, 0, 5) }

  around do |example|
    travel_to(Time.utc(2026, 10, 30))
    example.run
  ensure
    travel_back
  end

  before do
    stub_pdf_generation
    create_or_update_customer({external_id: "daily-customer", timezone: "UTC", currency: "USD"})

    api_call do
      post_with_token(organization, "/api/v2/products", {product: {
        name: "Daily fixed", code: "daily-product", product_type: "fixed"
      }})
    end
    api_call do
      post_with_token(organization, "/api/v2/rate_cards", {rate_card: {
        name: "Daily arrears", code: "daily-card", product_code: "daily-product", currency: "USD",
        billing_timing: "arrears", proration: false,
        rates: [{
          code: "daily-rate", effective_from: started_at.iso8601, rate_model: "standard",
          billing_interval_count: 1, billing_interval_unit: "day", rate_properties: {amount: "10"}
        }]
      }})
    end
    api_call do
      post_with_token(organization, "/api/v2/plans", {plan: {name: "Daily plan", code: "daily-plan", currency: "USD"}})
    end
    api_call do
      post_with_token(organization, "/api/v2/plans/daily-plan/applied_rate_cards", {
        applied_rate_card: {rate_card_code: "daily-card", units: 1}
      })
    end
    travel_to(started_at + 5.minutes) do
      api_call do
        post_with_token(organization, "/api/v2/contracts", {contract: {
          code: "daily-contract", external_id: "daily-contract", external_customer_id: "daily-customer", plan_code: "daily-plan",
          started_at: started_at.iso8601
        }})
      end
    end
  end

  it "persists the missing daily operations without processing or duplicating them" do
    travel_to(first_tick) do
      perform_enqueued_jobs { Clock::ScheduleBillingOperationsJob.perform_now }
    end

    invoice = Invoice.where(customer:).sole
    completed = card.billing_operations.completed.sole
    fee_ids = invoice.fees.order(:id).pluck(:id)
    expect(invoice).to have_attributes(status: "finalized", total_amount_cents: 1_000) # 1 unit * $10 per day.
    expect(fee_ids.size).to eq(1)
    expect(completed).to have_attributes(
      billing_at: Time.utc(2026, 11, 1), target_cycle_started_at: started_at,
      processed_at: first_tick, invoice_id: invoice.id
    )
    expect(card.reload.next_billing_at).to eq(Time.utc(2026, 11, 2))

    travel_to(catchup_tick) do
      Clock::ScheduleBillingOperationsJob.perform_now
      perform_all_enqueued_jobs(except: [BillingOperations::ProcessJob])

      pending = card.billing_operations.pending.order(:billing_at).to_a
      pending_ids = pending.map(&:id)
      expect(pending.map(&:billing_at)).to eq((2..19).map { Time.utc(2026, 11, it) })
      expect(pending.map(&:target_cycle_started_at)).to eq((1..18).map { Time.utc(2026, 11, it) })
      expect(pending.map(&:reason).uniq).to eq(["periodic_continuation"])
      expect(pending.map(&:processed_at).uniq).to eq([nil])
      expect(card.billing_operations.where(billing_at: Time.utc(2026, 11, 20)..)).to be_empty
      expect(completed.reload).to have_attributes(processed_at: first_tick, invoice_id: invoice.id)
      expect(Invoice.where(customer:).pluck(:id)).to eq([invoice.id])
      expect(invoice.reload.fees.order(:id).pluck(:id)).to eq(fee_ids)
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 11, 2))

      Clock::ScheduleBillingOperationsJob.perform_now
      perform_all_enqueued_jobs(except: [BillingOperations::ProcessJob])

      expect(card.billing_operations.pending.order(:billing_at).pluck(:id)).to eq(pending_ids)
      expect(card.billing_operations.count).to eq(19)
      expect(Invoice.where(customer:).pluck(:id)).to eq([invoice.id])
      expect(invoice.reload.fees.order(:id).pluck(:id)).to eq(fee_ids)
      expect(card.reload.next_billing_at).to eq(Time.utc(2026, 11, 2))
    end
  end
end
