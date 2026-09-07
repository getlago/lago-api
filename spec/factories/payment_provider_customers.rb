# frozen_string_literal: true

FactoryBot.define do
  factory :stripe_customer, class: "PaymentProviderCustomers::StripeCustomer" do
    customer
    organization { customer.organization }

    provider_customer_id { "cus_#{SecureRandom.hex}" }
    provider_payment_methods { %w[card sepa_debit] }
  end

  # The reserved manual connection: a null-provider row keyed by code "lago_manual" (no dedicated STI
  # class; the base type is stamped explicitly since the column is NOT NULL).
  factory :manual_payment_provider_customer, class: "PaymentProviderCustomers::BaseCustomer" do
    customer
    organization { customer.organization }

    type { "PaymentProviderCustomers::BaseCustomer" }
    code { "lago_manual" }
  end

  factory :gocardless_customer, class: "PaymentProviderCustomers::GocardlessCustomer" do
    customer
    organization { customer.organization }

    provider_customer_id { SecureRandom.uuid }
  end

  factory :cashfree_customer, class: "PaymentProviderCustomers::CashfreeCustomer" do
    customer
    organization { customer.organization }

    provider_customer_id { SecureRandom.uuid }
  end

  factory :adyen_customer, class: "PaymentProviderCustomers::AdyenCustomer" do
    customer
    organization { customer.organization }

    provider_customer_id { SecureRandom.uuid }
  end

  factory :moneyhash_customer, class: "PaymentProviderCustomers::MoneyhashCustomer" do
    customer
    organization { customer.organization }

    provider_customer_id { SecureRandom.uuid }
  end
  factory :flutterwave_customer, class: "PaymentProviderCustomers::FlutterwaveCustomer" do
    customer
    organization { customer.organization }
    payment_provider { association(:flutterwave_provider, organization: organization) }

    provider_customer_id { SecureRandom.uuid }
  end
end
