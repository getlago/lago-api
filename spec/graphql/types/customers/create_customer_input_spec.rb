# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Customers::CreateCustomerInput do
  subject { described_class }

  it { is_expected.to accept_argument(:address_line1).of_type('String') }
  it { is_expected.to accept_argument(:address_line2).of_type('String') }
  it { is_expected.to accept_argument(:city).of_type('String') }
  it { is_expected.to accept_argument(:country).of_type('CountryCode') }
  it { is_expected.to accept_argument(:currency).of_type('CurrencyEnum') }
  it { is_expected.to accept_argument(:customer_type).of_type('CustomerTypeEnum') }
  it { is_expected.to accept_argument(:email).of_type('String') }
  it { is_expected.to accept_argument(:external_id).of_type('String!') }
  it { is_expected.to accept_argument(:external_salesforce_id).of_type('String') }
  it { is_expected.to accept_argument(:firstname).of_type('String') }
  it { is_expected.to accept_argument(:invoice_grace_period).of_type('Int') }
  it { is_expected.to accept_argument(:lastname).of_type('String') }
  it { is_expected.to accept_argument(:legal_name).of_type('String') }
  it { is_expected.to accept_argument(:legal_number).of_type('String') }
  it { is_expected.to accept_argument(:logo_url).of_type('String') }
  it { is_expected.to accept_argument(:name).of_type('String') }
  it { is_expected.to accept_argument(:net_payment_term).of_type('Int') }
  it { is_expected.to accept_argument(:phone).of_type('String') }
  it { is_expected.to accept_argument(:state).of_type('String') }
  it { is_expected.to accept_argument(:tax_codes).of_type('[String!]') }
  it { is_expected.to accept_argument(:tax_identification_number).of_type('String') }
  it { is_expected.to accept_argument(:timezone).of_type('TimezoneEnum') }
  it { is_expected.to accept_argument(:url).of_type('String') }
  it { is_expected.to accept_argument(:zipcode).of_type('String') }
  it { is_expected.to accept_argument(:shipping_address).of_type('CustomerAddressInput') }
  it { is_expected.to accept_argument(:metadata).of_type('[CustomerMetadataInput!]') }
  it { is_expected.to accept_argument(:payment_provider).of_type('ProviderTypeEnum') }
  it { is_expected.to accept_argument(:payment_provider_code).of_type('String') }
  it { is_expected.to accept_argument(:provider_customer).of_type('ProviderCustomerInput') }
  it { is_expected.to accept_argument(:integration_customers).of_type('[IntegrationCustomerInput!]') }
  it { is_expected.to accept_argument(:billing_configuration).of_type('CustomerBillingConfigurationInput') }
end
