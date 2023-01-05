# frozen_string_literal: true

require 'rails_helper'

describe 'Invoices Scenarios', :invoices_scenarios, type: :request do
  # This performs any enqueued-jobs, and continues doing so until the queue is empty.
  # Lots of the jobs enqueue other jobs as part of their work, and this ensures that
  # everything that's supposed to happen, happens.
  def perform_all_enqueued_jobs
    # Drain ActiveJobs and Sidekiq jobs
    until enqueued_jobs.empty?
      perform_enqueued_jobs
      Sidekiq::Worker.drain_all
    end
  end

  let(:organization) { create(:organization, webhook_url: nil) }

  context 'when invoice is paid in advance and grace period' do
    let(:customer) { create(:customer, organization:, invoice_grace_period: 3) }
    let(:plan) { create(:plan, pay_in_advance: true, organization:, amount_cents: 1000) }
    let(:datetime) { DateTime.new(2022, 12, 15) }
    let(:metric) { create(:billable_metric, organization:) }

    before do
      subscription_service = Subscriptions::CreateService.new
      subscription_service.create_from_api(
        organization:,
        params: {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: plan.code,
          started_at: datetime,
          subscription_at: datetime,
        },
      )

      subscription = Subscription.order(created_at: :desc).first
      subscription.update!(created_at: datetime)

      Invoices::SubscriptionService.new(
        subscriptions: [subscription],
        timestamp: datetime.to_i,
        recurring: false,
      ).create

      invoice = Invoice.order(created_at: :desc).first
      invoice.update!(created_at: datetime)

      create(:standard_charge, plan:, billable_metric: metric, properties: { amount: '1' })
    end

    it 'terminates the pay in advance subscription' do
      invoice = Invoice.order(created_at: :desc).first
      subscription = invoice.subscriptions.first

      # 17 days - From 15th Dec. to 31st Dec.
      expect(invoice).to be_draft
      expect(invoice.total_amount_cents).to eq(658)

      # Terminate subscription on Dec. 20th
      current_date = DateTime.parse('20 Dec 2022')

      travel_to(current_date) do
        expect {
          delete_with_token(organization, "/api/v1/subscriptions/#{subscription.external_id}")
        }.to change { subscription.reload.status }.from('active').to('terminated')
      end

      perform_all_enqueued_jobs

      binding.break
    end

    it 'refreshes and finalizes invoices' do
      invoice = Invoice.order(created_at: :desc).first
      subscription = invoice.subscriptions.first

      # 17 days - From 15th Dec. to 31st Dec.
      expect(invoice.total_amount_cents).to eq(658)

      # Create an event for the subscription
      create(:event, subscription:, code: metric.code, timestamp: datetime + 1.day)

      # Paid in advance invoice amount should not change
      expect {
        put_with_token(organization, "/api/v1/invoices/#{invoice.id}/refresh", {})
      }.not_to change { invoice.reload.total_amount_cents }

      # Create an event for the subscription
      create(:event, subscription:, timestamp: datetime + 2.days, code: metric.code)

      # Paid in advance invoice should not change
      expect {
        put_with_token(organization, "/api/v1/invoices/#{invoice.id}/refresh", {})
      }.not_to change { invoice.reload.total_amount_cents }

      # Next month: Billing
      new_datetime = DateTime.new(2023, 1, 1)

      Invoices::SubscriptionService.new(
        subscriptions: [subscription],
        timestamp: new_datetime.to_i,
        recurring: false,
      ).create

      expect(subscription.invoices.count).to eq(2)
      new_invoice = subscription.invoices.order(created_at: :desc).first
      expect(new_invoice.total_amount_cents).to eq(1440) # (1000 + 200) * 1.2

      # Create event
      create(:event, subscription:, timestamp: datetime + 3.days, code: metric.code)

      # Nothing change in the invoice for the pay in advance subscription
      expect {
        put_with_token(organization, "/api/v1/invoices/#{invoice.id}/refresh", {})
      }.not_to change { invoice.reload.total_amount_cents }

      expect {
        put_with_token(organization, "/api/v1/invoices/#{new_invoice.id}/refresh", {})
      }.to change { new_invoice.reload.total_amount_cents }.from(1440).to(1560) # (1000 + 200 + 100) * 1.2

      # Finalize invoices
      expect {
        put_with_token(organization, "/api/v1/invoices/#{invoice.id}/finalize", {})
      }.to change { invoice.reload.status }.from('draft').to('finalized')

      expect {
        put_with_token(organization, "/api/v1/invoices/#{new_invoice.id}/finalize", {})
      }.to change { new_invoice.reload.status }.from('draft').to('finalized')

      expect(invoice.total_amount_cents).to eq(658)
      expect(new_invoice.total_amount_cents).to eq(1560)
    end
  end
end
