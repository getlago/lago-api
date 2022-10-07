# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field :login_user, mutation: Mutations::LoginUser
    field :register_user, mutation: Mutations::RegisterUser

    field :update_organization, mutation: Mutations::Organizations::Update

    field :create_billable_metric, mutation: Mutations::BillableMetrics::Create
    field :update_billable_metric, mutation: Mutations::BillableMetrics::Update
    field :destroy_billable_metric, mutation: Mutations::BillableMetrics::Destroy

    field :create_plan, mutation: Mutations::Plans::Create
    field :update_plan, mutation: Mutations::Plans::Update
    field :destroy_plan, mutation: Mutations::Plans::Destroy

    field :create_customer, mutation: Mutations::Customers::Create
    field :update_customer, mutation: Mutations::Customers::Update
    field :update_customer_vat_rate, mutation: Mutations::Customers::UpdateVatRate
    field :destroy_customer, mutation: Mutations::Customers::Destroy

    field :create_subscription, mutation: Mutations::Subscriptions::Create
    field :update_subscription, mutation: Mutations::Subscriptions::Update
    field :terminate_subscription, mutation: Mutations::Subscriptions::Terminate

    field :create_coupon, mutation: Mutations::Coupons::Create
    field :update_coupon, mutation: Mutations::Coupons::Update
    field :destroy_coupon, mutation: Mutations::Coupons::Destroy
    field :terminate_coupon, mutation: Mutations::Coupons::Terminate

    field :create_applied_coupon, mutation: Mutations::AppliedCoupons::Create
    field :terminate_applied_coupon, mutation: Mutations::AppliedCoupons::Terminate

    field :create_add_on, mutation: Mutations::AddOns::Create
    field :update_add_on, mutation: Mutations::AddOns::Update
    field :destroy_add_on, mutation: Mutations::AddOns::Destroy

    field :create_applied_add_on, mutation: Mutations::AppliedAddOns::Create

    field :destroy_payment_provider, mutation: Mutations::PaymentProviders::Destroy
    field :add_stripe_payment_provider, mutation: Mutations::PaymentProviders::Stripe

    field :download_credit_note, mutation: Mutations::CreditNotes::Download
    field :download_invoice, mutation: Mutations::Invoices::Download

    field :create_customer_wallet, mutation: Mutations::Wallets::Create
    field :update_customer_wallet, mutation: Mutations::Wallets::Update
    field :terminate_customer_wallet, mutation: Mutations::Wallets::Terminate

    field :create_customer_wallet_transaction, mutation: Mutations::WalletTransactions::Create

    field :create_invite, mutation: Mutations::Invites::Create
    field :accept_invite, mutation: Mutations::Invites::Accept
    field :revoke_invite, mutation: Mutations::Invites::Revoke
    field :revoke_membership, mutation: Mutations::Memberships::Revoke
  end
end
