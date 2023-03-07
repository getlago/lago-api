# frozen_string_literal: true

module ScenariosHelper
  ### Customers

  def create_or_update_customer(params)
    post_with_token(organization, '/api/v1/customers', { customer: params })
    perform_all_enqueued_jobs
  end

  def delete_customer(customer)
    delete_with_token(organization, "/api/v1/customers/#{customer.external_id}")
  end

  ### Plans

  def delete_plan(plan)
    delete_with_token(organization, "/api/v1/plans/#{plan.code}")
  end

  ### Subscriptions

  def create_subscription(params)
    post_with_token(organization, '/api/v1/subscriptions', { subscription: params })
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

  ### Coupons

  def create_coupon(params)
    post_with_token(organization, '/api/v1/coupons', { coupon: params })
  end

  def apply_coupon(params)
    post_with_token(organization, '/api/v1/applied_coupons', { applied_coupon: params })
  end

  ### Wallets

  def create_wallet(params)
    post_with_token(organization, '/api/v1/wallets', { wallet: params })
  end

  ### Events

  def create_event(params)
    post_with_token(organization, '/api/v1/events', { event: params })

    perform_all_enqueued_jobs
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
    perform_all_enqueued_jobs
  end
end
