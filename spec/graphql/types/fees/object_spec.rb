# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Fees::Object do
  subject { described_class }

  it { is_expected.to have_field(:invoice_display_name).of_type('String') }
  it { is_expected.to have_field(:charge).of_type('Charge') }
  it { is_expected.to have_field(:currency).of_type('CurrencyEnum!') }
  it { is_expected.to have_field(:subscription).of_type('Subscription') }
  it { is_expected.to have_field(:true_up_fee).of_type('Fee') }
  it { is_expected.to have_field(:true_up_parent_fee).of_type('Fee') }
  it { is_expected.to have_field(:creditable_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:events_count).of_type('BigInt') }
  it { is_expected.to have_field(:fee_type).of_type('FeeTypesEnum!') }
  it { is_expected.to have_field(:taxes_amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:taxes_rate).of_type('Float') }
  it { is_expected.to have_field(:units).of_type('Float!') }
  it { is_expected.to have_field(:applied_taxes).of_type('[FeeAppliedTax!]') }
  it { is_expected.to have_field(:adjusted_fee).of_type('Boolean!') }
  it { is_expected.to have_field(:adjusted_fee_type).of_type('AdjustedFeeTypeEnum') }
  it { is_expected.to have_field(:grouped_by).of_type('JSON!') }
end
