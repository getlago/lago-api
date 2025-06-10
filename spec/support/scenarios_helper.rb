# frozen_string_literal: true

module ScenariosHelper
  def api_call
    yield
    perform_all_enqueued_jobs
    json.with_indifferent_access
  end

  def clock_job
    yield
    perform_all_enqueued_jobs
  end

  ### Organizations

  def update_organization(params)
    api_call do
      put_with_token(organization, "/api/v1/organizations", {organization: params})
    end
  end

  ### Billing entities

  def update_billing_entity(billing_entity, params)
    # TODO: use the endpoint to update the billing entity instead when available
    BillingEntities::UpdateService.call!(billing_entity: billing_entity.reload, params:)
  end

  ### Billable metrics

  def create_metric(params)
    api_call do
      post_with_token(organization, "/api/v1/billable_metrics", {billable_metric: params})
    end
  end

  def update_metric(metric, params)
    api_call do
      put_with_token(organization, "/api/v1/billable_metrics/#{metric.code}", {billable_metric: params})
    end
  end

  ### Customers

  def create_or_update_customer(params)
    api_call do
      post_with_token(organization, "/api/v1/customers", {customer: params})
    end
  end

  def delete_customer(customer)
    api_call do
      delete_with_token(organization, "/api/v1/customers/#{customer.external_id}")
    end
  end

  def fetch_current_usage(customer:, subscription: customer.subscriptions.first)
    api_call do
      url = "/api/v1/customers/#{customer.external_id}/current_usage?external_subscription_id=#{subscription.external_id}"
      get_with_token(organization, url)
    end
  end

  ### Plans

  def create_plan(params)
    api_call do
      post_with_token(organization, "/api/v1/plans", {plan: params})
    end
  end

  def update_plan(plan, params)
    api_call do
      put_with_token(organization, "/api/v1/plans/#{plan.code}", {plan: params})
    end
  end

  def delete_plan(plan)
    api_call do
      delete_with_token(organization, "/api/v1/plans/#{plan.code}")
    end
  end

  ### Subscriptions

  def create_subscription(params, authorization = nil)
    payload = {subscription: params}
    payload[:authorization] = authorization if authorization
    api_call do
      post_with_token(organization, "/api/v1/subscriptions", payload)
    end
  end

  def terminate_subscription(subscription)
    api_call do
      delete_with_token(organization, "/api/v1/subscriptions/#{subscription.external_id}")
    end
  end

  def create_alert(sub_external_id, params)
    api_call do
      post_with_token(organization, "/api/v1/subscriptions/#{sub_external_id}/alerts", {alert: params})
    end
  end

  ### Invoices

  def refresh_invoice(invoice)
    api_call do
      put_with_token(organization, "/api/v1/invoices/#{invoice.id}/refresh", {})
    end
  end

  def finalize_invoice(invoice)
    api_call do
      put_with_token(organization, "/api/v1/invoices/#{invoice.id}/finalize", {})
    end
  end

  def update_invoice(invoice, params)
    api_call do
      put_with_token(organization, "/api/v1/invoices/#{invoice.id}", {invoice: params})
    end
  end

  def void_invoice(invoice, params = {})
    post_with_token(organization, "/api/v1/invoices/#{invoice.id}/void", params)
    perform_all_enqueued_jobs
    invoice.reload
  end

  def create_one_off_invoice(customer, addons, taxes: [], units: 1)
    api_call do
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
          units:,
          unit_amount_cents: fee.amount_cents,
          tax_codes: taxes
        }
        create_invoice_params[:fees].push(fee_addon_params)
      end
      post_with_token(organization, "/api/v1/invoices", {invoice: create_invoice_params})
    end
  end

  def retry_invoice_payment(invoice_id)
    api_call do
      post_with_token(organization, "/api/v1/invoices/#{invoice_id}/retry_payment")
    end
  end

  ### Coupons

  def create_coupon(params)
    api_call do
      post_with_token(organization, "/api/v1/coupons", {coupon: params})
    end
  end

  def apply_coupon(params)
    api_call do
      post_with_token(organization, "/api/v1/applied_coupons", {applied_coupon: params})
    end
  end

  ### Taxes

  def create_tax(params)
    api_call do
      post_with_token(organization, "/api/v1/taxes", {tax: params})
    end
  end

  # The mock always return a valid response,
  # To get an invalid response, simply use a invalid format (like YY123)
  def mock_vies_check!(vat_number)
    valvat = instance_double(Valvat)
    allow(Valvat).to receive(:new).with(vat_number).and_return(valvat)
    allow(valvat).to receive(:exists?).with(detail: true).and_return({
      countryCode: vat_number[0..1].upcase,
      vatNumber: vat_number.upcase
    })
  end

  ### Wallets

  def create_wallet(params)
    api_call do
      post_with_token(organization, "/api/v1/wallets", {wallet: params})
    end
  end

  def create_wallet_transaction(params)
    api_call do
      post_with_token(organization, "/api/v1/wallet_transactions", {wallet_transaction: params})
    end
  end

  def recalculate_wallet_balances
    Clock::RefreshLifetimeUsagesJob.perform_later
    Clock::RefreshWalletsOngoingBalanceJob.perform_later
    perform_all_enqueued_jobs
  end

  ### Events

  def ingest_event(subscription, billable_metric, amount)
    create_event({
      transaction_id: SecureRandom.uuid,
      code: billable_metric.code,
      external_subscription_id: subscription.external_id,
      properties: {billable_metric&.field_name => amount}
    })
    perform_usage_update
  end

  def create_event(params)
    api_call do
      post_with_token(organization, "/api/v1/events", {event: params})
    end
  end

  ### Credit notes

  def create_credit_note(params)
    api_call do
      post_with_token(organization, "/api/v1/credit_notes", {credit_note: params})
    end
  end

  def estimate_credit_note(params)
    api_call do
      post_with_token(organization, "/api/v1/credit_notes/estimate", {credit_note: params})
    end
  end

  ### Analytics

  def get_analytics(organization:, analytics_type:)
    api_call do
      get_with_token(organization, "/api/v1/analytics/#{analytics_type}", months: 20)
    end
  end

  ### Payment methods

  def setup_stripe_for(customer:)
    stripe_provider = create(:stripe_provider, organization:)
    create(:stripe_customer, customer_id: customer.id, payment_provider: stripe_provider)
    customer.update!(payment_provider: "stripe", payment_provider_code: stripe_provider.code)
  end

  ### Fees

  def update_fee(fee_id, params)
    api_call do
      put_with_token(organization, "/api/v1/fees/#{fee_id}", {fee: params})
    end
  end

  # Clock jobs

  def perform_billing
    clock_job do
      Clock::SubscriptionsBillerJob.perform_later
      Clock::FreeTrialSubscriptionsBillerJob.perform_later
    end
    perform_usage_update
  end

  def perform_invoices_refresh
    clock_job do
      Clock::RefreshDraftInvoicesJob.perform_later
    end
  end

  def perform_finalize_refresh
    clock_job do
      Clock::FinalizeInvoicesJob.perform_later
    end
  end

  def perform_usage_update
    clock_job do
      Clock::ComputeAllDailyUsagesJob.perform_later
      Clock::RefreshLifetimeUsagesJob.perform_later
      Clock::ProcessAllSubscriptionActivitiesJob.perform_later
    end
  end

  def perform_overdue_balance_update
    clock_job do
      Clock::MarkInvoicesAsPaymentOverdueJob.perform_later
    end
  end

  def perform_dunning
    clock_job do
      Clock::ProcessDunningCampaignsJob.perform_later
    end
  end
end
