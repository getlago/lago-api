# frozen_string_literal: true

require 'rails_helper'

describe 'Billing Minimum Commitments In Arrears Scenario', :scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }
  let(:timezone) { 'UTC' }
  let(:customer) { create(:customer, organization:, timezone:) }
  let(:pdf_generator) { instance_double(Utils::PdfGenerator) }
  let(:pdf_file) { StringIO.new(File.read(Rails.root.join('spec/fixtures/blank.pdf'))) }
  let(:pdf_result) { OpenStruct.new(io: pdf_file) }

  let(:plan) do
    create(
      :plan,
      name: 'In Arrears',
      code: 'in_arrears',
      organization:,
      amount_cents: 10_000,
      interval: plan_interval,
      pay_in_advance: false,
      bill_charges_monthly:,
    )
  end

  let(:invoice) { subscription.reload.invoices.order(sequential_id: :desc).first }
  let(:subscription) { customer.subscriptions.first.reload }

  let(:billable_metric_advance_metered) do
    create(
      :billable_metric,
      organization:,
      name: 'Metered in advance',
      code: 'advance_metered',
      aggregation_type: 'sum_agg',
      field_name: 'total',
      recurring: false,
    )
  end

  let(:billable_metric_metered) do
    create(
      :billable_metric,
      organization:,
      name: 'Metered in arrears',
      code: 'metered',
      aggregation_type: 'sum_agg',
      field_name: 'total',
      recurring: false,
    )
  end

  let(:billable_metric_recurring_advance) do
    create(
      :billable_metric,
      organization:,
      name: 'In advance recurring',
      code: 'recurring_advance',
      aggregation_type: 'sum_agg',
      field_name: 'total',
      recurring: true,
    )
  end

  let(:billing_time) { 'anniversary' }
  let(:plan_interval) { 'yearly' }
  let(:subscription_time) { DateTime.new(2024, 3, 1, 10) }
  let(:minimum_commitment) { create(:commitment, :minimum_commitment, plan:, amount_cents: 1_000_000) }

  before do
    allow(Utils::PdfGenerator).to receive(:new).and_return(pdf_generator)
    allow(pdf_generator).to receive(:call).and_return(pdf_result)

    minimum_commitment

    create(
      :standard_charge,
      :pay_in_advance,
      billable_metric: billable_metric_advance_metered,
      invoiceable: true,
      plan:,
      properties: { amount: '1' },
    )

    create(
      :standard_charge,
      billable_metric: billable_metric_metered,
      invoiceable: true,
      plan:,
      properties: { amount: '1' },
    )

    create(
      :standard_charge,
      :pay_in_advance,
      billable_metric: billable_metric_recurring_advance,
      invoiceable: true,
      plan:,
      properties: { amount: '1' },
    )

    # Create the subscription
    travel_to(subscription_time) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code,
          billing_time:,
        },
      )
    end

    travel_to(subscription_time + 1.hour) do
      create_event(
        {
          code: billable_metric_advance_metered.code,
          transaction_id: SecureRandom.uuid,
          external_customer_id: customer.external_id,
          properties: { total: '2' },
        },
      )

      create_event(
        {
          code: billable_metric_metered.code,
          transaction_id: SecureRandom.uuid,
          external_customer_id: customer.external_id,
          properties: { total: '1' },
        },
      )

      create_event(
        {
          code: billable_metric_advance_metered.code,
          transaction_id: SecureRandom.uuid,
          external_customer_id: customer.external_id,
          properties: { total: '30' },
        },
      )
    end
  end

  context 'when billed monthly' do
    let(:bill_charges_monthly) { true }

    context 'when subscription is billed for the first period' do
      it 'creates an invoice with no minimum commitment fee' do
        travel_to(subscription_time + 1.month + 1.day) do
          Subscriptions::BillingService.new.call
          perform_all_enqueued_jobs

          expect(invoice.fees.commitment_kind.count).to eq(0)
        end
      end
    end

    context 'when subscription is billed for the last period' do
      before do
        (1..12).each do |i|
          travel_to(subscription_time + i.month) do
            if i == 5
              create_event(
                {
                  code: billable_metric_advance_metered.code,
                  transaction_id: SecureRandom.uuid,
                  external_customer_id: customer.external_id,
                  properties: { total: '55' },
                },
              )
            end

            if i == 11
              create_event(
                {
                  code: billable_metric_metered.code,
                  transaction_id: SecureRandom.uuid,
                  external_customer_id: customer.external_id,
                  properties: { total: '1' },
                },
              )
            end

            Subscriptions::BillingService.new.call
            perform_all_enqueued_jobs
          end
        end
      end

      it 'creates an invoice with minimum commitment fee' do
        travel_to(subscription_time + 1.year + 1.month) do
          aggregate_failures do
            expect(invoice.fees.commitment_kind.count).to eq(1)
            expect(invoice.fees.commitment_kind.sum(:amount_cents)).to eq(981_100)
          end
        end
      end
    end
  end
end
