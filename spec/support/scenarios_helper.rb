# frozen_string_literal: true

module ScenariosHelper
  ### Billable metrics

  def create_metric(params)
    post_with_token(organization, '/api/v1/billable_metrics', {billable_metric: params})
  end

  def update_metric(metric, params)
    put_with_token(organization, "/api/v1/billable_metrics/#{metric.code}", {billable_metric: params})
  end

  ### Customers

  def create_or_update_customer(params)
    post_with_token(organization, '/api/v1/customers', {customer: params})
    perform_all_enqueued_jobs
  end

  def delete_customer(customer)
    delete_with_token(organization, "/api/v1/customers/#{customer.external_id}")
  end

  def fetch_current_usage(customer:, subscription: customer.subscriptions.first)
    get_with_token(
      organization,
      "/api/v1/customers/#{customer.external_id}/current_usage?external_subscription_id=#{subscription.external_id}"
    )
  end

  ### Plans

  def create_plan(params)
    post_with_token(organization, '/api/v1/plans', {plan: params})
  end

  def update_plan(plan, params)
    put_with_token(organization, "/api/v1/plans/#{plan.code}", {plan: params})
  end

  def delete_plan(plan)
    delete_with_token(organization, "/api/v1/plans/#{plan.code}")
  end

  ### Subscriptions

  def create_subscription(params)
    post_with_token(organization, '/api/v1/subscriptions', {subscription: params})
    perform_all_enqueued_jobs
  end

  def terminate_subscription(subscription)
    delete_with_token(organization, "/api/v1/subscriptions/#{subscription.external_id}")
    perform_all_enqueued_jobs
  end

  ### Invoices

  def refresh_invoice(invoice)
    put_with_token(organization, "/api/v1/invoices/#{invoice.id}/refresh", {})
  end

  def finalize_invoice(invoice)
    put_with_token(organization, "/api/v1/invoices/#{invoice.id}/finalize", {})
  end

  def update_invoice(invoice, params)
    put_with_token(organization, "/api/v1/invoices/#{invoice.id}", {invoice: params})
  end

  def create_one_off_invoice(customer, addons)
    create_invoice_params = {
      external_customer_id: customer.external_id,
      currency: "EUR",
      fees: [],
      timestamp: Time.zone.now.to_i
    }
    addons.each do |fee|
      fee_addon_params = {
        add_on_id: fee.id,
        add_on_code: fee.code,
        name: fee.name,
        units: 1,
        unit_amount_cents: fee.amount_cents,
        tax_codes: [
          tax.code
        ]
      }
      create_invoice_params[:fees].push(fee_addon_params)
    end
    post_with_token(organization, "/api/v1/invoices", {invoice: create_invoice_params})
  end

  ### Coupons

  def create_coupon(params)
    post_with_token(organization, '/api/v1/coupons', {coupon: params})
  end

  def apply_coupon(params)
    post_with_token(organization, '/api/v1/applied_coupons', {applied_coupon: params})
  end

  ### Taxes

  def create_tax(params)
    post_with_token(organization, '/api/v1/taxes', {tax: params})
  end

  ### Wallets

  def create_wallet(params)
    post_with_token(organization, '/api/v1/wallets', {wallet: params})
    perform_all_enqueued_jobs
  end

  def create_wallet_transaction(params)
    post_with_token(organization, '/api/v1/wallet_transactions', {wallet_transaction: params})
    perform_all_enqueued_jobs
  end

  ### Events

  def create_event(params)
    post_with_token(organization, '/api/v1/events', {event: params})
    perform_all_enqueued_jobs
    JSON.parse(response.body) unless response.body.empty?
  end

  ### Credit notes

  def create_credit_note(params)
    post_with_token(organization, '/api/v1/credit_notes', {credit_note: params})
  end

  def estimate_credit_note(params)
    post_with_token(organization, '/api/v1/credit_notes/estimate', {credit_note: params})
  end

  ### Payment methods

  def setup_stripe_for(customer:)
    stripe_provider = create(:stripe_provider, organization:)
    create(:stripe_customer, customer_id: customer.id, payment_provider: stripe_provider)
    customer.update!(payment_provider: 'stripe', payment_provider_code: stripe_provider.code)
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

  def perform_billing
    Clock::SubscriptionsBillerJob.perform_later
    Clock::FreeTrialSubscriptionsBillerJob.perform_later
    perform_all_enqueued_jobs
  end

  def perform_invoices_refresh
    Clock::RefreshDraftInvoicesJob.perform_later
    perform_all_enqueued_jobs
  end

  def perform_finalize_refresh
    Clock::FinalizeInvoicesJob.perform_later
    perform_all_enqueued_jobs
  end

  def perform_usage_update
    Clock::ComputeAllDailyUsagesJob.perform_later
    Clock::RefreshLifetimeUsagesJob.perform_later
    perform_all_enqueued_jobs
  end
end
