# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Customers::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type("ID!") }

  it { is_expected.to have_field(:external_id).of_type("String!") }
  it { is_expected.to have_field(:name).of_type("String") }
  it { is_expected.to have_field(:sequential_id).of_type("String!") }
  it { is_expected.to have_field(:slug).of_type("String!") }

  it { is_expected.to have_field(:address_line1).of_type("String") }
  it { is_expected.to have_field(:address_line2).of_type("String") }

  it { is_expected.to have_field(:applicable_timezone).of_type("TimezoneEnum!") }
  it { is_expected.to have_field(:city).of_type("String") }
  it { is_expected.to have_field(:country).of_type("CountryCode") }
  it { is_expected.to have_field(:currency).of_type("CurrencyEnum") }
  it { is_expected.to have_field(:email).of_type("String") }
  it { is_expected.to have_field(:external_salesforce_id).of_type("String") }
  it { is_expected.to have_field(:invoice_grace_period).of_type("Int") }
  it { is_expected.to have_field(:legal_name).of_type("String") }
  it { is_expected.to have_field(:legal_number).of_type("String") }
  it { is_expected.to have_field(:logo_url).of_type("String") }
  it { is_expected.to have_field(:net_payment_term).of_type("Int") }
  it { is_expected.to have_field(:payment_provider).of_type("ProviderTypeEnum") }
  it { is_expected.to have_field(:payment_provider_code).of_type("String") }
  it { is_expected.to have_field(:phone).of_type("String") }
  it { is_expected.to have_field(:state).of_type("String") }
  it { is_expected.to have_field(:tax_identification_number).of_type("String") }
  it { is_expected.to have_field(:timezone).of_type("TimezoneEnum") }
  it { is_expected.to have_field(:url).of_type("String") }
  it { is_expected.to have_field(:zipcode).of_type("String") }

  it { is_expected.to have_field(:metadata).of_type("[CustomerMetadata!]") }

  it { is_expected.to have_field(:billing_configuration).of_type("CustomerBillingConfiguration") }

  it { is_expected.to have_field(:provider_customer).of_type("ProviderCustomer") }
  it { is_expected.to have_field(:subscriptions).of_type("[Subscription!]!") }

  it { is_expected.to have_field(:invoices).of_type("[Invoice!]") }

  it { is_expected.to have_field(:applied_add_ons).of_type("[AppliedAddOn!]") }
  it { is_expected.to have_field(:applied_coupons).of_type("[AppliedCoupon!]") }
  it { is_expected.to have_field(:taxes).of_type("[Tax!]") }

  it { is_expected.to have_field(:credit_notes).of_type("[CreditNote!]") }

  it { is_expected.to have_field(:created_at).of_type("ISO8601DateTime!") }
  it { is_expected.to have_field(:deleted_at).of_type("ISO8601DateTime") }
  it { is_expected.to have_field(:updated_at).of_type("ISO8601DateTime!") }

  it { is_expected.to have_field(:active_subscriptions_count).of_type("Int!") }
  it { is_expected.to have_field(:credit_notes_balance_amount_cents).of_type("BigInt!") }
  it { is_expected.to have_field(:credit_notes_credits_available_count).of_type("Int!") }
  it { is_expected.to have_field(:has_active_wallet).of_type("Boolean!") }
  it { is_expected.to have_field(:has_credit_notes).of_type("Boolean!") }

  it { is_expected.to have_field(:can_edit_attributes).of_type("Boolean!") }
end
