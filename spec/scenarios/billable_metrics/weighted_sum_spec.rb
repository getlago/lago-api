# frozen_string_literal: true

require 'rails_helper'

describe 'Aggregation - Weighted Sum Scenarios', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:customer) { create(:customer, organization:) }

  let(:plan) { create(:plan, organization:, amount_cents: 0) }
  let(:billable_metric) { create(:weighted_sum_billable_metric, :recurring, organization:) }
  let(:charge) { create(:standard_charge, plan:, billable_metric:, properties: { amount: '1000' }) }

  before { charge }

  it 'creates fees and keeps the units between periods' do
    travel_to(DateTime.new(2023, 3, 5)) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code,
        },
      )
    end

    subscription = customer.subscriptions.first

    travel_to(DateTime.new(2023, 3, 7)) do
      create_event(
        {
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          external_customer_id: customer.external_id,
          properties: { value: '2500' },
        },
      )

      fetch_current_usage(customer:)
      expect(json[:customer_usage][:total_amount_cents]).to eq(116)
      expect(json[:customer_usage][:charges_usage][0][:units]).to eq('0.00115740794324441817')
    end

    travel_to(DateTime.new(2023, 4, 1)) do
      expect do
        Subscriptions::BillingService.new.call
        perform_all_enqueued_jobs
      end.to change { subscription.reload.invoices.count }.from(0).to(1)
        .and change { customer.reload.quantified_events.count }.from(0).to(1)
    end

    invoice = subscription.invoices.first
    expect(invoice.fees.charge.count).to eq(1)

    fee = invoice.fees.charge.first
    expect(fee.amount_cents).to eq(116)
    expect(fee.units.round(5)).to eq(0.00116)
    expect(fee.total_aggregated_units).to eq(2500)

    quantified_event = QuantifiedEvent.last
    expect(quantified_event.properties['total_aggregated_units']).to eq('2500.0')

    travel_to(DateTime.new(2023, 4, 4)) do
      create_event(
        {
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          external_customer_id: customer.external_id,
          properties: { value: '-2000' },
        },
      )
    end

    travel_to(DateTime.new(2023, 4, 6)) do
      create_event(
        {
          code: billable_metric.code,
          transaction_id: SecureRandom.uuid,
          external_customer_id: customer.external_id,
          properties: { value: '-200' },
        },
      )

      fetch_current_usage(customer:)
      expect(json[:customer_usage][:total_amount_cents]).to eq(1268)
      expect(json[:customer_usage][:charges_usage][0][:units]).to eq('0.01267746920010291043')
    end

    travel_to(DateTime.new(2023, 5, 1)) do
      expect do
        Subscriptions::BillingService.new.call
        perform_all_enqueued_jobs
      end.to change { subscription.reload.invoices.count }.from(1).to(2)
        .and change { customer.reload.quantified_events.count }.from(1).to(2)
    end

    invoice = subscription.invoices.order(:created_at).last
    expect(invoice.fees.charge.count).to eq(1)

    fee = invoice.fees.charge.first
    expect(fee.amount_cents).to eq(1268)
    expect(fee.units.round(5)).to eq(0.01268)
    expect(fee.total_aggregated_units).to eq(300)

    quantified_event = QuantifiedEvent.order(:created_at).last
    expect(quantified_event.properties['total_aggregated_units']).to eq('300.0')
  end
end
