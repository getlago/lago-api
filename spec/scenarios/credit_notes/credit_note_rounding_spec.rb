# frozen_string_literal: true

require "rails_helper"

describe "Credit note rounding issues Scenarios", :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: []) }
  let(:customer) { create(:customer, organization:) }

  let(:tax) { create(:tax, :applied_to_billing_entity, organization:, rate: 25) }
  let(:plan) { create(:plan, organization:, interval: :monthly, amount_cents:, pay_in_advance: true) }

  around { |test| lago_premium!(&test) }

  before do
    tax
    plan
  end

  context "when the thing is greater" do
    let(:amount_cents) { 20000 }

    it "handles the rounding issues" do
      # Creates the subscription
      travel_to(Time.zone.parse("2025-09-18T16:00:00Z")) do
        create_subscription({
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code,
          billing_time: :anniversary
        })
      end

      subscription = customer.subscriptions.last
      invoice = customer.invoices.last
      expect(invoice.fees_amount_cents).to eq(20000)
      expect(invoice.taxes_amount_cents).to eq(5000)
      expect(invoice.total_amount_cents).to eq(25000)

      # Finalize the invoice
      travel_to(Time.zone.parse("2025-09-18T16:30:00Z")) do
        update_invoice(invoice, {payment_status: "succeeded"})
      end

      # Terminate subscription
      travel_to(Time.zone.parse("2025-09-18T16:40:00Z")) do
        terminate_subscription(subscription)
      end

      # Fetch the credit note
      credit_note = customer.credit_notes.sole
      expect(credit_note).to have_attributes(
        sub_total_excluding_taxes_amount_cents: 19333,
        taxes_amount_cents: 4833,
        credit_amount_cents: 24166,
        total_amount_cents: 24166
      )
    end
  end

  context "when the other thing is greater" do
    let(:amount_cents) { 16000 }

    it "handles the rounding issues" do
      # Creates the subscription
      travel_to(Time.zone.parse("2025-09-18T16:00:00Z")) do
        create_subscription({
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code,
          billing_time: :anniversary
        })
      end

      subscription = customer.subscriptions.last
      invoice = customer.invoices.last
      expect(invoice.fees_amount_cents).to eq(16000)
      expect(invoice.taxes_amount_cents).to eq(4000)
      expect(invoice.total_amount_cents).to eq(20000)

      # Finalize the invoice
      travel_to(Time.zone.parse("2025-09-18T16:30:00Z")) do
        update_invoice(invoice, {payment_status: "succeeded"})
      end

      # Terminate subscription
      travel_to(Time.zone.parse("2025-09-18T16:40:00Z")) do
        terminate_subscription(subscription)
      end

      # Fetch the credit note
      credit_note = customer.credit_notes.sole
      item = credit_note.items.sole
      expect(item).to have_attributes(
        amount_cents: 15467,
        precise_amount_cents: 0.1546666666e5
      )
      expect(credit_note).to have_attributes(
        sub_total_excluding_taxes_amount_cents: 15467,
        taxes_amount_cents: 3867,
        credit_amount_cents: 19334,
        total_amount_cents: 19334
      )
      expect(credit_note.applied_taxes.sole).to have_attributes(
        amount_cents: 3867
      )
    end
  end

  context "when total credit is different" do
    let(:tax) { create(:tax, :applied_to_billing_entity, organization:, rate: 23.33) }
    let(:plan) { create(:plan, organization:, interval: :weekly, amount_cents: 2999, pay_in_advance: true) }

    it "handles the rounding issues" do
      travel_to(Time.zone.parse("2025-10-06T16:00:00Z")) do
        create_subscription({
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code,
          billing_time: :calendar
        })
      end

      subscription = customer.subscriptions.last
      invoice = customer.invoices.last
      expect(invoice.fees_amount_cents).to eq(2999)
      expect(invoice.taxes_amount_cents).to eq(700)
      expect(invoice.total_amount_cents).to eq(2999 + 700)

      travel_to(Time.zone.parse("2025-10-06T16:30:00Z")) do
        update_invoice(invoice, {payment_status: "succeeded"})
        terminate_subscription(subscription)
      end

      credit_note = customer.credit_notes.sole
      item = credit_note.items.sole
      expect(item).to have_attributes(
        amount_cents: 2571,
        precise_amount_cents: 2570.57142
      )

      expect(credit_note).to have_attributes(
        sub_total_excluding_taxes_amount_cents: 2571,
        taxes_amount_cents: 600,
        credit_amount_cents: 3171,
        total_amount_cents: 3171
      )
      expect(credit_note.applied_taxes.sole).to have_attributes(
        amount_cents: 600
      )
    end
  end
end
