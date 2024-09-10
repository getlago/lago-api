# frozen_string_literal: true

require 'rails_helper'
RSpec.describe Types::Organizations::CurrentOrganizationType do
  subject { described_class }

  it { is_expected.to be < ::Types::Organizations::BaseOrganizationType }

  it { is_expected.to have_field(:id).of_type('ID!') }

  it { is_expected.to have_field(:default_currency).of_type('CurrencyEnum!') }
  it { is_expected.to have_field(:email).of_type('String') }
  it { is_expected.to have_field(:legal_name).of_type('String') }
  it { is_expected.to have_field(:legal_number).of_type('String') }
  it { is_expected.to have_field(:logo_url).of_type('String') }
  it { is_expected.to have_field(:name).of_type('String!') }
  it { is_expected.to have_field(:tax_identification_number).of_type('String') }

  it { is_expected.to have_field(:address_line1).of_type('String') }
  it { is_expected.to have_field(:address_line2).of_type('String') }
  it { is_expected.to have_field(:city).of_type('String') }
  it { is_expected.to have_field(:country).of_type('CountryCode') }
  it { is_expected.to have_field(:net_payment_term).of_type('Int!') }
  it { is_expected.to have_field(:state).of_type('String') }
  it { is_expected.to have_field(:zipcode).of_type('String') }

  it { is_expected.to have_field(:api_key).of_type('String').with_permission('developers:keys:manage') }
  it { is_expected.to have_field(:webhook_url).of_type('String').with_permission('developers:manage') }

  it { is_expected.to have_field(:timezone).of_type('TimezoneEnum') }

  it { is_expected.to have_field(:created_at).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:updated_at).of_type('ISO8601DateTime!') }

  it { is_expected.to have_field(:finalize_zero_amount_invoice).of_type('Boolean!') }
  it { is_expected.to have_field(:billing_configuration).of_type('OrganizationBillingConfiguration').with_permission('organization:invoices:view') }
  it { is_expected.to have_field(:email_settings).of_type('[EmailSettingsEnum!]').with_permission('organization:emails:view') }
  it { is_expected.to have_field(:taxes).of_type('[Tax!]').with_permission('organization:taxes:view') }

  it { is_expected.to have_field(:adyen_payment_providers).of_type('[AdyenProvider!]').with_permission('organization:integrations:view') }
  it { is_expected.to have_field(:gocardless_payment_providers).of_type('[GocardlessProvider!]').with_permission('organization:integrations:view') }
  it { is_expected.to have_field(:stripe_payment_providers).of_type('[StripeProvider!]').with_permission('organization:integrations:view') }
end
