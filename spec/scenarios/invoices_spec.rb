# frozen_string_literal: true

require 'rails_helper'

describe 'Invoices Scenarios', :invoices_scenarios, type: :request do
  let(:organization) { create(:organization, webhook_url: nil) }

  context 'when invoice is paid in advance and grace period' do
    let(:customer) { create(:customer, organization:, invoice_grace_period: 3) }
    let(:plan) { create(:plan, pay_in_advance: true, organization:, amount_cents: 1000) }
    let(:metric) { create(:billable_metric, organization:) }

    it 'terminates the pay in advance subscription with credit note lesser than amount' do
      ### 15 Dec: Create subscription + charge.
      dec15 = DateTime.new(2022, 12, 15)

      travel_to(dec15) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        create(:standard_charge, plan:, billable_metric: metric, properties: { amount: '3' })

        subscription_invoice = Invoice.order(created_at: :desc).first
        expect(subscription_invoice).to be_draft
        expect(subscription_invoice.total_amount_cents).to eq(658) # 17 days - From 15th Dec. to 31st Dec.
      end

      subscription = Subscription.order(created_at: :desc).first
      subscription_invoice = subscription.invoices.first

      ### 17 Dec: Create event + refresh.
      travel_to(DateTime.new(2022, 12, 17)) do
        create(:event, subscription:, code: metric.code)
        create(:event, subscription:, code: metric.code)

        expect {
          refresh_invoice(subscription_invoice)
        }.not_to change { subscription_invoice.reload.total_amount_cents }
      end

      ### 20 Dec: Terminate subscription + refresh.
      dec20 = DateTime.new(2022, 12, 20)

      travel_to(dec20) do
        expect {
          terminate_subscription(subscription)
        }.to change { subscription.reload.status }.from('active').to('terminated')
          .and change { subscription_invoice.reload.credit_notes.count }.from(0).to(1)
          .and change { subscription.invoices.count }.from(1).to(2)

        # Credit note is created (31 - 20) * 548 / 17.0 * 1.2 = 425.
        credit_note = subscription_invoice.credit_notes.first
        expect(credit_note.credit_amount_cents).to eq(425)
        expect(credit_note.balance_amount_cents).to eq(0) # 425 - 600

        # Invoice for termination is created
        termination_invoice = subscription.invoices.order(created_at: :desc).first

        # Total amount should reflect the credit note (720 - 425)
        expect(termination_invoice.total_amount_cents).to eq(295)
        expect(termination_invoice.credits.first.amount_cents).to eq(425)
        expect(termination_invoice.credit_notes.count).to eq(0)

        # Refresh pay in advance invoice
        expect {
          refresh_invoice(subscription_invoice)
        }.not_to change { subscription_invoice.reload.total_amount_cents }
        expect(credit_note.reload.credit_amount_cents).to eq(425)

        # Refresh termination invoice
        expect {
          refresh_invoice(termination_invoice)
        }.not_to change { termination_invoice.reload.total_amount_cents }

        # Finalize pay in advance invoice
        expect {
          finalize_invoice(subscription_invoice)
        }.to change { subscription_invoice.reload.status }.from('draft').to('finalized')
        expect(subscription_invoice.total_amount_cents).to eq(658)

        # Finalize termination invoice
        expect {
          finalize_invoice(termination_invoice)
        }.to change { termination_invoice.reload.status }.from('draft').to('finalized')

        # Total amount should reflect the credit note
        expect(termination_invoice.total_amount_cents).to eq(295)
      end
    end

    it 'terminates the pay in advance subscription with credit note greater than amount' do
      ### 15 Dec: Create subscription + charge.
      dec15 = DateTime.new(2022, 12, 15)

      travel_to(dec15) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        create(:standard_charge, plan:, billable_metric: metric, properties: { amount: '1' })

        subscription_invoice = Invoice.order(created_at: :desc).first
        expect(subscription_invoice).to be_draft
        expect(subscription_invoice.total_amount_cents).to eq(658) # 17 days - From 15th Dec. to 31st Dec.
      end

      subscription = Subscription.order(created_at: :desc).first
      subscription_invoice = subscription.invoices.first

      ### 17 Dec: Create event + refresh.
      travel_to(DateTime.new(2022, 12, 17)) do
        create(:event, subscription:, code: metric.code)

        expect {
          refresh_invoice(subscription_invoice)
        }.not_to change { subscription_invoice.reload.total_amount_cents }
      end

      ### 20 Dec: Terminate subscription + refresh.
      dec20 = DateTime.new(2022, 12, 20)

      travel_to(dec20) do
        expect {
          terminate_subscription(subscription)
        }.to change { subscription.reload.status }.from('active').to('terminated')
          .and change { subscription_invoice.reload.credit_notes.count }.from(0).to(1)
          .and change { subscription.invoices.count }.from(1).to(2)

        # Credit note is created (31 - 20) * 548 / 17.0 * 1.2 = 425.
        credit_note = subscription_invoice.credit_notes.first
        expect(credit_note.credit_amount_cents).to eq(425)
        expect(credit_note.balance_amount_cents).to eq(305) # 425 - 120

        # Invoice for termination is created
        termination_invoice = subscription.invoices.order(created_at: :desc).first

        # Total amount should reflect the credit note (120 - 425)
        expect(termination_invoice.total_amount_cents).to eq(0)
        expect(termination_invoice.credits.first.amount_cents).to eq(120)
        expect(termination_invoice.credit_notes.count).to eq(0)

        # Refresh pay in advance invoice
        expect {
          refresh_invoice(subscription_invoice)
        }.not_to change { subscription_invoice.reload.total_amount_cents }
        expect(credit_note.reload.credit_amount_cents).to eq(425)

        # Refresh termination invoice
        expect {
          refresh_invoice(termination_invoice)
        }.not_to change { termination_invoice.reload.total_amount_cents }

        # Finalize pay in advance invoice
        expect {
          finalize_invoice(subscription_invoice)
        }.to change { subscription_invoice.reload.status }.from('draft').to('finalized')
        expect(subscription_invoice.total_amount_cents).to eq(658)

        # Finalize termination invoice
        expect {
          finalize_invoice(termination_invoice)
        }.to change { termination_invoice.reload.status }.from('draft').to('finalized')

        # Total amount should reflect the credit note (120 - 425)
        expect(termination_invoice.total_amount_cents).to eq(0)
      end
    end

    it 'refreshes and finalizes invoices' do
      ### 15 Dec: Create subscription + charge.
      dec15 = DateTime.new(2022, 12, 15)

      travel_to(dec15) do
        create_subscription(
          {
            external_customer_id: customer.external_id,
            external_id: customer.external_id,
            plan_code: plan.code,
          },
        )

        create(:standard_charge, plan:, billable_metric: metric, properties: { amount: '1' })

        invoice = Invoice.order(created_at: :desc).first
        expect(invoice.total_amount_cents).to eq(658) # 17 days - From 15th Dec. to 31st Dec.
      end

      subscription = Subscription.order(created_at: :desc).first
      invoice = subscription.invoices.first

      ### 16 Dec: Create event + refresh.
      travel_to(DateTime.new(2022, 12, 16)) do
        create(:event, subscription:, code: metric.code)

        # Paid in advance invoice amount does not change.
        expect {
          refresh_invoice(invoice)
        }.not_to change { invoice.reload.total_amount_cents }
      end

      ### 17 Dec: Create event + refresh.
      travel_to(DateTime.new(2022, 12, 17)) do
        create(:event, subscription:, code: metric.code)

        # Paid in advance invoice amount does not change.
        expect {
          refresh_invoice(invoice)
        }.not_to change { invoice.reload.total_amount_cents }
      end

      ### 1 Jan: Billing + refresh + finalize.
      travel_to(DateTime.new(2023, 1, 1)) do
        perform_billing

        expect(subscription.invoices.count).to eq(2)
        new_invoice = subscription.invoices.order(created_at: :desc).first
        expect(new_invoice.total_amount_cents).to eq(1440) # (1000 + 200) * 1.2

        # Create event for Dec 18.
        create(:event, subscription:, timestamp: DateTime.new(2022, 12, 18), code: metric.code)

        # Paid in advance invoice amount does not change.
        expect {
          refresh_invoice(invoice)
        }.not_to change { invoice.reload.total_amount_cents }

        # Usage invoice amount is updated.
        expect {
          refresh_invoice(new_invoice)
        }.to change { new_invoice.reload.total_amount_cents }.from(1440).to(1560) # (1000 + 200 + 100) * 1.2

        # Finalize invoices.
        expect {
          finalize_invoice(invoice)
        }.to change { invoice.reload.status }.from('draft').to('finalized')

        expect {
          finalize_invoice(new_invoice)
        }.to change { new_invoice.reload.status }.from('draft').to('finalized')

        expect(invoice.total_amount_cents).to eq(658)
        expect(new_invoice.total_amount_cents).to eq(1560)
      end
    end
  end

  # This performs any enqueued-jobs, and continues doing so until the queue is empty.
  # Lots of the jobs enqueue other jobs as part of their work, and this ensures that
  # everything that's supposed to happen, happens.
  def perform_all_enqueued_jobs
    until enqueued_jobs.empty?
      perform_enqueued_jobs
      Sidekiq::Worker.drain_all
    end
  end

  def create_subscription(params)
    post_with_token(organization, '/api/v1/subscriptions', { subscription: params })
    perform_all_enqueued_jobs
  end

  def perform_billing
    Clock::SubscriptionsBillerJob.perform_later
    perform_all_enqueued_jobs
  end

  def refresh_invoice(invoice)
    put_with_token(organization, "/api/v1/invoices/#{invoice.id}/refresh", {})
  end

  def finalize_invoice(invoice)
    put_with_token(organization, "/api/v1/invoices/#{invoice.id}/finalize", {})
  end

  def terminate_subscription(subscription)
    delete_with_token(organization, "/api/v1/subscriptions/#{subscription.external_id}")
    perform_all_enqueued_jobs
  end
end
