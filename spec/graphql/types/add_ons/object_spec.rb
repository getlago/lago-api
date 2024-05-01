# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::AddOns::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID!') }
  it { is_expected.to have_field(:organization).of_type('Organization') }
  it { is_expected.to have_field(:code).of_type('String!') }
  it { is_expected.to have_field(:description).of_type('String') }
  it { is_expected.to have_field(:invoice_display_name).of_type('String') }
  it { is_expected.to have_field(:name).of_type('String!') }
  it { is_expected.to have_field(:amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:amount_currency).of_type('CurrencyEnum!') }
  it { is_expected.to have_field(:created_at).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:deleted_at).of_type('ISO8601DateTime') }
  it { is_expected.to have_field(:updated_at).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:applied_add_ons_count).of_type('Int!') }
  it { is_expected.to have_field(:customers_count).of_type('Int!') }
  it { is_expected.to have_field(:taxes).of_type('[Tax!]') }
  it { is_expected.to have_field(:integration_mappings).of_type('[NetsuiteMapping!]') }
end
