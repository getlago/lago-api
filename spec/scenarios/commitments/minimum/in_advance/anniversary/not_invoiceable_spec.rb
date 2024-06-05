# frozen_string_literal: true

require 'rails_helper'
require 'json'

describe 'Billing scenario', :scenarios, type: :request do
  let(:organization) { create(:organization, email_settings: ['invoice.finalized'], webhook_url: nil) }
  let(:timezone) { 'UTC' }
  let(:customer) { create(:customer, organization:, timezone:) }
  let(:pdf_generator) { instance_double(Utils::PdfGenerator) }
  let(:pdf_file) { StringIO.new(File.read(Rails.root.join('spec/fixtures/blank.pdf'))) }
  let(:pdf_result) { OpenStruct.new(io: pdf_file) }

  let(:plan) do
    create(
      :plan,
      name: 'Monthly advance payment',
      code: 'monthly_plan',
      organization:,
      amount_cents: 10_00,
      interval: :monthly,
      pay_in_advance:,

      amount_currency: "EUR"
    )
  end

  let(:invoice) { subscription.reload.invoices.order(sequential_id: :desc).first }
  let(:subscription) { customer.subscriptions.first.reload }

  let(:billable_metric_advance_recurring) do
    create(
      :billable_metric,
      organization:,
      name: 'seat',
      code: 'seat',
      aggregation_type: 'sum_agg',
      field_name: 'seats',
      recurring: true
    )
  end

  let(:subscription_time) { DateTime.new(2024, 6, 5) }

  before do
    allow(Utils::PdfGenerator).to receive(:new).and_return(pdf_generator)
    allow(pdf_generator).to receive(:call).and_return(pdf_result)

    create(
      :standard_charge,
      pay_in_advance:,
      invoiceable:,
      billable_metric: billable_metric_advance_recurring,
      plan:,
      properties: {amount: '5'},
      prorated:
    )

    # Create the subscription
    travel_to(subscription_time) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code,
          billing_time: :anniversary
        }
      )
    end

    travel_to(DateTime.new(2024, 6, 25)) do
      create_event(
        {
          code: billable_metric_advance_recurring.code,
          transaction_id: SecureRandom.uuid,
          external_customer_id: customer.external_id,
          properties: {seats: 10}
        }
      )
    end

    travel_to(DateTime.new(2024, 6, 29)) do
      create_event(
        {
          code: billable_metric_advance_recurring.code,
          transaction_id: SecureRandom.uuid,
          external_customer_id: customer.external_id,
          properties: {seats: -5}
        }
      )
    end

    travel_to(DateTime.new(2024, 7, 10)) do
      create_event(
        {
          code: billable_metric_advance_recurring.code,
          transaction_id: SecureRandom.uuid,
          external_customer_id: customer.external_id,
          properties: {seats: 32}
        }
      )
    end
  end

  context 'when prorated payed in advance' do
    let(:prorated) { true }
    let(:pay_in_advance) { true }
    let(:invoiceable) { false }

    it 'Checks a whole year invoiceable false' do
      subscription = customer.subscriptions.first

      (1..12).each do |i|
        travel_to(subscription_time + i.months) do
          Subscriptions::BillingService.new.call
          expect { perform_all_enqueued_jobs }.to change { subscription.reload.invoices.count }.by(1)
          invoice = subscription.invoices.order(:created_at).last

          # This should not be 10, it should be the previous months' usage
          expect(invoice.total_amount_cents).not_to eq(10_00)
        end
      end

      expect(subscription.reload.invoices.count).to eq(13) # 12 + 1 in advance
    end
  end
end
