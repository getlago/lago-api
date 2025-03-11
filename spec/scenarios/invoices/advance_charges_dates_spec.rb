# frozen_string_literal: true

require "rails_helper"

describe "Advance Charges Invoices Scenarios", :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }
  let(:tax_rate) { 20 }
  let(:billable_metric) { create(:unique_count_billable_metric, organization:, code: "cards", recurring: true) }
  let(:plan) { create(:plan, organization:, pay_in_advance: true, amount_cents: 49) }
  let(:plan_upgrade) { create(:plan, organization:, pay_in_advance: true, amount_cents: 259) }
  let(:external_subscription_id) { "sub_#{SecureRandom.hex}" }
  let(:bm_amount) { 30.12 }

  def send_card_event!(item_id = SecureRandom.uuid)
    create_event({
      code: billable_metric.code,
      transaction_id: "tr_#{SecureRandom.hex(10)}",
      external_customer_id: customer.external_id,
      external_subscription_id:,
      properties: {item_id:}
    })
  end

  before do
    create(:tax, organization:, rate: tax_rate)
    create(:standard_charge, regroup_paid_fees: "invoice", pay_in_advance: true, invoiceable: false, prorated: true, billable_metric:, plan:, properties: {amount: bm_amount.to_s, grouped_by: nil})
    create(:standard_charge, regroup_paid_fees: "invoice", pay_in_advance: true, invoiceable: false, prorated: true, billable_metric:, plan: plan_upgrade, properties: {amount: bm_amount.to_s, grouped_by: nil})
  end

  context "when subscription is renewed" do
    it "generates an invoice with the correct charges" do
      travel_to(DateTime.new(2024, 6, 5, 10)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: external_subscription_id,
            plan_code: plan.code
          }
        )
        perform_billing
        expect(customer.invoices.count).to eq(1)
      end

      initial_subscription = customer.subscriptions.sole

      # Create an event but keep it unpaid
      travel_to(DateTime.new(2024, 6, 12, 10)) do
        send_card_event! "card_1"
        expect(initial_subscription.fees.charge.where(invoice_id: nil).count).to eq(1)
      end

      upgraded_subscription = nil
      # Upgrade the subscription (so previous one is terminated)
      travel_to(DateTime.new(2024, 7, 7, 10)) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: external_subscription_id,
            plan_code: plan_upgrade.code
          }
        )

        upgraded_subscription = customer.subscriptions.where.not(id: initial_subscription.id).sole
        pp({
          upgraded_subscription: upgraded_subscription.id,
          initial_subscription: initial_subscription.id
        })
        expect(initial_subscription.reload).to be_terminated
        expect(customer.invoices.count).to eq(2) # initial sub invoice + upgraded sub invoice
        expect(upgraded_subscription.fees.charge.count).to eq 0
      end

      # Create an event but keep it unpaid
      travel_to(DateTime.new(2024, 7, 22, 10)) do
        send_card_event! "card_2"
        # one fee for each subscription
        expect(initial_subscription.fees.charge.where(invoice_id: nil).count).to eq(1)
        expect(upgraded_subscription.fees.charge.where(invoice_id: nil).count).to eq(1)
      end

      # In october, both fees are finally marked as paid
      travel_to(DateTime.new(2024, 10, 2, 10)) do
        [initial_subscription, upgraded_subscription].each do |subscription|
          subscription.fees.charge.where(invoice_id: nil).each do |fee|
            update_fee(fee, payment_status: :succeeded)
          end
        end
      end

      # In november, these fees should be added to the advance_charge invoice
      travel_to(DateTime.new(2024, 11, 1, 10)) do
        perform_billing
        invoice = customer.invoices.where(invoice_type: :advance_charges).sole
        expect(invoice.fees.count).to eq(2)
        pp(::V1::InvoiceSerializer.new(
          invoice,
          root_name: "invoice", includes: [:billing_periods]
        ).serialize[:billing_periods])
      end
    end
  end
end
