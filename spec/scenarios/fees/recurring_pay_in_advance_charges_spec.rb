# frozen_string_literal: true

require 'rails_helper'

describe 'Recurring Pay In Advance Charges', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }
  let(:billable_metric) { create(:unique_count_billable_metric, :recurring, organization:) }
  let(:plan) { create(:plan, organization:, amount_cents: 499_00, pay_in_advance: true) }
  let(:charge) { create(:charge, plan:, billable_metric:, pay_in_advance: true, invoiceable:, properties: {amount: '12'}) }

  context 'when invoiceable is false' do
    let(:invoiceable) { false }
    let(:external_subscription_id) { SecureRandom.uuid }
    let(:transaction_id) { SecureRandom.uuid }

    before do
      charge
    end

    it 'create fees when the period is renewed' do
      travel_to(Time.zone.parse('2024-03-05T12:12:00')) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: external_subscription_id,
            plan_code: plan.code
          }
        )
        perform_billing
        expect(customer.reload.invoices.count).to eq(1)
      end

      subscription = customer.subscriptions.sole

      travel_to(Time.zone.parse('2024-03-15T10:00:00')) do
        expect(subscription.fees.charge.count).to eq(0)

        res = create_event({
          code: billable_metric.code,
          transaction_id:,
          external_subscription_id:,
          properties: {unique_id: 'id_1'}
        })

        expect(subscription.fees.charge.count).to eq(1)

        fee = subscription.fees.charge.sole
        expect(fee.units).to eq(1)
        expect(fee.events_count).to eq(1)
        expect(fee.amount_cents).to eq(12_00)
        expect(fee.invoice_id).to be_nil
        expect(fee.pay_in_advance_event_id).to eq(res.dig('event', 'lago_id'))

        properties = fee.properties
        expect(properties["charges_from_datetime"]).to eq('2024-03-05T12:12:00.000Z')
        expect(properties["charges_to_datetime"]).to eq('2024-03-31T23:59:59.999Z')
      end

      travel_to(Time.zone.parse('2024-04-01T00:12:00')) do
        perform_billing
        expect(customer.reload.invoices.count).to eq(2)
        expect(subscription.fees.charge.count).to eq(2)

        fee = subscription.fees.charge.order(created_at: :desc).first
        expect(fee.units).to eq(1)
        expect(fee.events_count).to eq(1)
        expect(fee.amount_cents).to eq(12_00)

        properties = fee.properties
        expect(properties["charges_from_datetime"]).to eq('2024-04-01T00:00:00.000Z')
        expect(properties["charges_to_datetime"]).to eq('2024-04-30T23:59:59.999Z')
      end
    end
  end
end
