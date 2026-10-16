# frozen_string_literal: true

require "rails_helper"

describe "Adjusted Fixed Charge Fees Scenario", :premium, transaction: false do
  subject(:adjust_fee) do
    AdjustedFees::CreateService.call(
      invoice: renewal_invoice,
      params: {
        subscription_id: subscription.id,
        fixed_charge_id: storage_fixed_charge.id,
        units: 10,
        unit_precise_amount: "480"
      }
    )
  end

  let(:organization) { create(:organization, webhook_url: nil, email_settings: "") }
  let(:customer) do
    create(:customer, organization:, timezone: "UTC", invoice_grace_period: 30)
  end
  let(:subscription_at) { DateTime.new(2025, 10, 5, 22, 10) }
  let(:renewal_at) { subscription_at + 1.year }
  let(:plan) do
    create(
      :plan,
      organization:,
      interval: "yearly",
      amount_cents: 100,
      pay_in_advance: true,
      bill_fixed_charges_monthly: false
    )
  end
  let(:storage_add_on) { create(:add_on, organization:) }
  let(:seats_add_on) { create(:add_on, organization:) }
  let(:storage_fixed_charge) do
    create(
      :fixed_charge,
      :graduated,
      plan:,
      add_on: storage_add_on,
      units: 0,
      pay_in_advance: true,
      prorated: false,
      properties: {
        graduated_ranges: [
          {from_value: 0, to_value: nil, per_unit_amount: "480", flat_amount: "0"}
        ]
      }
    )
  end
  let(:seats_fixed_charge) do
    create(
      :fixed_charge,
      :graduated,
      plan:,
      add_on: seats_add_on,
      units: 1,
      pay_in_advance: true,
      prorated: false,
      properties: {
        graduated_ranges: [
          {from_value: 0, to_value: nil, per_unit_amount: "100", flat_amount: "0"}
        ]
      }
    )
  end
  let(:subscription) { customer.subscriptions.sole }
  let(:renewal_invoice) { customer.invoices.subscription.order(created_at: :desc).first }

  before do
    travel_to(subscription_at) do
      storage_fixed_charge
      seats_fixed_charge
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code,
          billing_time: "anniversary",
          subscription_at: subscription_at.iso8601
        }
      )
    end
  end

  it "adds a missing pay-in-advance fixed charge fee to the renewal draft" do
    travel_to(renewal_at) do
      perform_billing

      expect(renewal_invoice).to be_draft
      expect(renewal_invoice.total_amount_cents).to eq(10_100)
      expect(renewal_invoice.fees.exists?(fixed_charge: storage_fixed_charge)).to be(false)

      result = adjust_fee

      expect(result).to be_success
      expect(result.fee).to have_attributes(
        fixed_charge: storage_fixed_charge,
        units: 10,
        amount_cents: 480_000
      )
      expect(result.adjusted_fee.fee).to eq(result.fee)
      expect(renewal_invoice.reload.total_amount_cents).to eq(490_100)
    end
  end
end
