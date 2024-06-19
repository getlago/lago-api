# frozen_string_literal: true

require 'rails_helper'

describe 'Grouped In Advance Charges Invoices Scenarios', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }
  let(:tax_rate) { 20 }
  let(:billable_metric) { create(:unique_count_billable_metric, organization:, code: 'cards', recurring: false) }
  let(:plan) { create(:plan, organization:, pay_in_advance: true, amount_cents: 49) }
  let(:external_subscription_id) { SecureRandom.uuid }

  def send_card_event!(item_id = SecureRandom.uuid)
    create_event({
      code: billable_metric.code,
      transaction_id: SecureRandom.uuid,
      external_customer_id: customer.external_id,
      external_subscription_id:,
      properties: {item_id:}
    })
  end

  before do
    create(:tax, organization:, rate: tax_rate)
    create(:standard_charge, pay_in_advance: true, invoiceable: false, prorated: true, billable_metric:, plan:, properties: {amount: '30'})
  end

  context 'with a subscription is renewed' do
    it 'generates an invoice with the correct charges' do

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

      subscription = customer.subscriptions.sole

      (1..5).each do |i|
        travel_to(DateTime.new(2024, 6, 10 + i, 10)) do
          send_card_event! "card_#{i}"
          expect(subscription.fees.charge.count).to eq(i)
          expect(subscription.fees.charge.order(created_at: :desc).first.amount_cents).to eq((21 - i) * 100)
        end
      end

      expect(subscription.fees.charge.where(invoice_id: nil).count).to eq 5
      subscription.fees.charge.order(created_at: :asc).limit(3).update!(payment_status: :succeeded)

      travel_to(DateTime.new(2024, 7, 1, 0, 10)) do
        perform_billing
        expect(customer.invoices.count).to eq(4)
        expect(subscription.fees.charge.where(invoice_id: nil).count).to eq 0

        paid = customer.invoices.where(invoice_type: :grouped_in_advance_charges, payment_status: :succeeded).sole
        expect(paid.fees_amount_cents).to eq((20 + 19 + 18) * 100)

        unpaid = customer.invoices.where(invoice_type: :grouped_in_advance_charges, payment_status: :pending).sole
        expect(unpaid.fees_amount_cents).to eq((17 + 16) * 100)
      end
    end
  end
end
