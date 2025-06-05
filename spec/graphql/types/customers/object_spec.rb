# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Customers::Object do
  subject { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:billing_entity).of_type("BillingEntity!")

    expect(subject).to have_field(:account_type).of_type("CustomerAccountTypeEnum!")
    expect(subject).to have_field(:customer_type).of_type(Types::Customers::CustomerTypeEnum)
    expect(subject).to have_field(:display_name).of_type("String!")
    expect(subject).to have_field(:external_id).of_type("String!")
    expect(subject).to have_field(:firstname).of_type("String")
    expect(subject).to have_field(:lastname).of_type("String")
    expect(subject).to have_field(:name).of_type("String")
    expect(subject).to have_field(:sequential_id).of_type("String!")
    expect(subject).to have_field(:slug).of_type("String!")

    expect(subject).to have_field(:address_line1).of_type("String")
    expect(subject).to have_field(:address_line2).of_type("String")

    expect(subject).to have_field(:applicable_timezone).of_type("TimezoneEnum!")
    expect(subject).to have_field(:city).of_type("String")
    expect(subject).to have_field(:country).of_type("CountryCode")
    expect(subject).to have_field(:currency).of_type("CurrencyEnum")
    expect(subject).to have_field(:email).of_type("String")
    expect(subject).to have_field(:external_salesforce_id).of_type("String")
    expect(subject).to have_field(:invoice_grace_period).of_type("Int")
    expect(subject).to have_field(:legal_name).of_type("String")
    expect(subject).to have_field(:legal_number).of_type("String")
    expect(subject).to have_field(:logo_url).of_type("String")
    expect(subject).to have_field(:net_payment_term).of_type("Int")
    expect(subject).to have_field(:payment_provider).of_type("ProviderTypeEnum")
    expect(subject).to have_field(:payment_provider_code).of_type("String")
    expect(subject).to have_field(:phone).of_type("String")
    expect(subject).to have_field(:state).of_type("String")
    expect(subject).to have_field(:tax_identification_number).of_type("String")
    expect(subject).to have_field(:timezone).of_type("TimezoneEnum")
    expect(subject).to have_field(:url).of_type("String")
    expect(subject).to have_field(:zipcode).of_type("String")

    expect(subject).to have_field(:metadata).of_type("[CustomerMetadata!]")

    expect(subject).to have_field(:billing_configuration).of_type("CustomerBillingConfiguration")

    expect(subject).to have_field(:shipping_address).of_type("CustomerAddress")

    expect(subject).to have_field(:anrok_customer).of_type("AnrokCustomer")
    expect(subject).to have_field(:avalara_customer).of_type("AvalaraCustomer")
    expect(subject).to have_field(:hubspot_customer).of_type("HubspotCustomer")
    expect(subject).to have_field(:netsuite_customer).of_type("NetsuiteCustomer")
    expect(subject).to have_field(:salesforce_customer).of_type("SalesforceCustomer")
    expect(subject).to have_field(:provider_customer).of_type("ProviderCustomer")
    expect(subject).to have_field(:subscriptions).of_type("[Subscription!]!")
    expect(subject).to have_field(:xero_customer).of_type("XeroCustomer")

    expect(subject).to have_field(:invoices).of_type("[Invoice!]")

    expect(subject).to have_field(:activity_logs).of_type("[ActivityLog!]")
    expect(subject).to have_field(:applied_add_ons).of_type("[AppliedAddOn!]")
    expect(subject).to have_field(:applied_coupons).of_type("[AppliedCoupon!]")
    expect(subject).to have_field(:taxes).of_type("[Tax!]")

    expect(subject).to have_field(:credit_notes).of_type("[CreditNote!]")

    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:deleted_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:updated_at).of_type("ISO8601DateTime!")

    expect(subject).to have_field(:active_subscriptions_count).of_type("Int!")
    expect(subject).to have_field(:credit_notes_balance_amount_cents).of_type("BigInt!")
    expect(subject).to have_field(:credit_notes_credits_available_count).of_type("Int!")
    expect(subject).to have_field(:has_active_wallet).of_type("Boolean!")
    expect(subject).to have_field(:has_credit_notes).of_type("Boolean!")
    expect(subject).to have_field(:has_overdue_invoices).of_type("Boolean!")

    expect(subject).to have_field(:can_edit_attributes).of_type("Boolean!")
    expect(subject).to have_field(:finalize_zero_amount_invoice).of_type("FinalizeZeroAmountInvoiceEnum")

    expect(subject).to have_field(:applied_dunning_campaign).of_type("DunningCampaign")
    expect(subject).to have_field(:exclude_from_dunning_campaign).of_type("Boolean!")
    expect(subject).to have_field(:last_dunning_campaign_attempt).of_type("Int!")
    expect(subject).to have_field(:last_dunning_campaign_attempt_at).of_type("ISO8601DateTime")
    expect(subject).to have_field(:configurable_invoice_custom_sections).of_type("[InvoiceCustomSection!]")
  end
end
