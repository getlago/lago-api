# frozen_string_literal: true

require 'rails_helper'

describe 'Adjusted Charge Fees Scenario', :scenarios, type: :request, transaction: false do
  let(:organization) { create(:organization, webhook_url: nil, email_settings: '') }

  let(:customer) { create(:customer, organization:, invoice_grace_period: 5) }
  let(:subscription_at) { DateTime.new(2023, 7, 19, 12, 12) }
  let(:billable_metric) { create(:billable_metric, organization:, aggregation_type: 'sum_agg', field_name: 'custom') }
  let(:unit_amount_cents) { nil }

  let(:adjusted_fee_params) do
    {
      invoice_display_name: 'test-name-25',
      unit_amount_cents:,
      units: 3,
    }
  end

  let(:monthly_plan) do
    create(
      :plan,
      organization:,
      interval: 'monthly',
      amount_cents: 12_900,
      pay_in_advance: false,
    )
  end

  around { |test| lago_premium!(&test) }

  context 'with adjusted units' do
    it 'creates invoices correctly' do
      # NOTE: Jul 19th: create the subscription
      travel_to(subscription_at) do
        create(
          :standard_charge,
          plan: monthly_plan,
          billable_metric:,
          properties: { amount: '5' },
        )

        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: monthly_plan.code,
            billing_time: 'anniversary',
            subscription_at: subscription_at.iso8601,
          },
        )
      end

      # NOTE: August 19th: Bill subscription
      travel_to(DateTime.new(2023, 8, 19, 12, 12)) do
        Subscriptions::BillingService.call
        perform_all_enqueued_jobs

        invoice = customer.invoices.order(created_at: :desc).first
        fee = Fee.charge_kind.where(invoice:).first

        expect(invoice.status).to eq('draft')
        expect(invoice.total_amount_cents).to eq(12_900)

        AdjustedFees::CreateService.call(organization:, fee:, params: adjusted_fee_params)
        perform_all_enqueued_jobs

        expect(invoice.reload.status).to eq('draft')
        expect(invoice.reload.total_amount_cents).to eq(12_900 + 1_500)
      end

      # NOTE: August 20th: Refresh and finalize invoice
      travel_to(DateTime.new(2023, 8, 20, 12, 12)) do
        invoice = customer.invoices.order(created_at: :desc).first

        Invoices::RefreshDraftJob.perform_later(invoice)
        perform_all_enqueued_jobs

        expect(invoice.reload.status).to eq('draft')
        expect(invoice.reload.total_amount_cents).to eq(12_900 + 1_500)

        Invoices::FinalizeJob.perform_later(invoice)
        perform_all_enqueued_jobs

        expect(invoice.reload.status).to eq('finalized')
        expect(invoice.reload.total_amount_cents).to eq(12_900 + 1_500)
      end
    end
  end

  context 'with adjusted amount' do
    let(:unit_amount_cents) { 15_000 }

    it 'creates invoices correctly' do
      # NOTE: Jul 19th: create the subscription
      travel_to(subscription_at) do
        create(
          :standard_charge,
          plan: monthly_plan,
          billable_metric:,
          properties: { amount: '10' },
        )

        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: monthly_plan.code,
            billing_time: 'anniversary',
            subscription_at: subscription_at.iso8601,
          },
        )
      end

      # NOTE: August 19th: Bill subscription
      travel_to(DateTime.new(2023, 8, 19, 12, 12)) do
        Subscriptions::BillingService.call
        perform_all_enqueued_jobs

        invoice = customer.invoices.order(created_at: :desc).first
        fee = Fee.charge_kind.where(invoice:).first

        expect(invoice.status).to eq('draft')
        expect(invoice.total_amount_cents).to eq(12_900)

        AdjustedFees::CreateService.call(organization:, fee:, params: adjusted_fee_params)
        perform_all_enqueued_jobs

        expect(invoice.reload.status).to eq('draft')
        expect(invoice.reload.total_amount_cents).to eq(12_900 + 45_000)
      end

      # NOTE: August 20th: Refresh and finalize invoice
      travel_to(DateTime.new(2023, 8, 20, 12, 12)) do
        invoice = customer.invoices.order(created_at: :desc).first

        Invoices::RefreshDraftJob.perform_later(invoice)
        perform_all_enqueued_jobs

        expect(invoice.reload.status).to eq('draft')
        expect(invoice.reload.total_amount_cents).to eq(12_900 + 45_000)

        Invoices::FinalizeJob.perform_later(invoice)
        perform_all_enqueued_jobs

        expect(invoice.reload.status).to eq('finalized')
        expect(invoice.reload.total_amount_cents).to eq(12_900 + 45_000)
      end
    end
  end
end
