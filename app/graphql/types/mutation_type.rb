# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field :login_user, mutation: Mutations::LoginUser
    field :register_user, mutation: Mutations::RegisterUser

    field :update_organization, mutation: Mutations::Organizations::Update

    field :create_billable_metric, mutation: Mutations::BillableMetrics::Create
    field :destroy_billable_metric, mutation: Mutations::BillableMetrics::Destroy
    field :update_billable_metric, mutation: Mutations::BillableMetrics::Update

    field :create_adjusted_fee, mutation: Mutations::AdjustedFees::Create

    field :create_plan, mutation: Mutations::Plans::Create
    field :destroy_plan, mutation: Mutations::Plans::Destroy
    field :update_plan, mutation: Mutations::Plans::Update

    field :create_customer, mutation: Mutations::Customers::Create
    field :destroy_customer, mutation: Mutations::Customers::Destroy
    field :update_customer, mutation: Mutations::Customers::Update
    field :update_customer_invoice_grace_period, mutation: Mutations::Customers::UpdateInvoiceGracePeriod

    field :download_customer_portal_invoice, mutation: Mutations::CustomerPortal::DownloadInvoice
    field :generate_customer_portal_url, mutation: Mutations::CustomerPortal::GenerateUrl

    field :create_subscription, mutation: Mutations::Subscriptions::Create
    field :terminate_subscription, mutation: Mutations::Subscriptions::Terminate
    field :update_subscription, mutation: Mutations::Subscriptions::Update

    field :create_coupon, mutation: Mutations::Coupons::Create
    field :destroy_coupon, mutation: Mutations::Coupons::Destroy
    field :terminate_coupon, mutation: Mutations::Coupons::Terminate
    field :update_coupon, mutation: Mutations::Coupons::Update

    field :create_applied_coupon, mutation: Mutations::AppliedCoupons::Create
    field :terminate_applied_coupon, mutation: Mutations::AppliedCoupons::Terminate

    field :create_add_on, mutation: Mutations::AddOns::Create
    field :destroy_add_on, mutation: Mutations::AddOns::Destroy
    field :update_add_on, mutation: Mutations::AddOns::Update

    field :add_adyen_payment_provider, mutation: Mutations::PaymentProviders::Adyen::Create
    field :add_gocardless_payment_provider, mutation: Mutations::PaymentProviders::Gocardless::Create
    field :add_stripe_payment_provider, mutation: Mutations::PaymentProviders::Stripe::Create

    field :update_adyen_payment_provider, mutation: Mutations::PaymentProviders::Adyen::Update
    field :update_gocardless_payment_provider, mutation: Mutations::PaymentProviders::Gocardless::Update
    field :update_stripe_payment_provider, mutation: Mutations::PaymentProviders::Stripe::Update

    field :destroy_payment_provider, mutation: Mutations::PaymentProviders::Destroy

    field :create_credit_note, mutation: Mutations::CreditNotes::Create
    field :download_credit_note, mutation: Mutations::CreditNotes::Download
    field :update_credit_note, mutation: Mutations::CreditNotes::Update
    field :void_credit_note, mutation: Mutations::CreditNotes::Void

    field :create_invoice, mutation: Mutations::Invoices::Create
    field :download_invoice, mutation: Mutations::Invoices::Download
    field :finalize_invoice, mutation: Mutations::Invoices::Finalize
    field :refresh_invoice, mutation: Mutations::Invoices::Refresh
    field :retry_all_invoice_payments, mutation: Mutations::Invoices::RetryAllPayments
    field :retry_invoice_payment, mutation: Mutations::Invoices::RetryPayment
    field :update_invoice, mutation: Mutations::Invoices::Update
    field :void_invoice, mutation: Mutations::Invoices::Void

    field :create_customer_wallet, mutation: Mutations::Wallets::Create
    field :terminate_customer_wallet, mutation: Mutations::Wallets::Terminate
    field :update_customer_wallet, mutation: Mutations::Wallets::Update

    field :create_customer_wallet_transaction, mutation: Mutations::WalletTransactions::Create

    field :accept_invite, mutation: Mutations::Invites::Accept
    field :create_invite, mutation: Mutations::Invites::Create
    field :revoke_invite, mutation: Mutations::Invites::Revoke
    field :revoke_membership, mutation: Mutations::Memberships::Revoke

    field :create_password_reset, mutation: Mutations::PasswordResets::Create
    field :reset_password, mutation: Mutations::PasswordResets::Reset

    field :create_tax, mutation: Mutations::Taxes::Create
    field :destroy_tax, mutation: Mutations::Taxes::Destroy
    field :update_tax, mutation: Mutations::Taxes::Update

    field :retry_webhook, mutation: Mutations::Webhooks::Retry

    field :create_webhook_endpoint, mutation: Mutations::WebhookEndpoints::Create
    field :destroy_webhook_endpoint, mutation: Mutations::WebhookEndpoints::Destroy
    field :update_webhook_endpoint, mutation: Mutations::WebhookEndpoints::Update
  end
end
