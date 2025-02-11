# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Fees::Object do
  subject { described_class }

  it do
    expect(subject).to have_field(:invoice_display_name).of_type('String')
    expect(subject).to have_field(:charge).of_type('Charge')
    expect(subject).to have_field(:currency).of_type('CurrencyEnum!')
    expect(subject).to have_field(:subscription).of_type('Subscription')
    expect(subject).to have_field(:true_up_fee).of_type('Fee')
    expect(subject).to have_field(:true_up_parent_fee).of_type('Fee')
    expect(subject).to have_field(:creditable_amount_cents).of_type('BigInt!')
    expect(subject).to have_field(:events_count).of_type('BigInt')
    expect(subject).to have_field(:fee_type).of_type('FeeTypesEnum!')
    expect(subject).to have_field(:taxes_amount_cents).of_type('BigInt!')
    expect(subject).to have_field(:taxes_rate).of_type('Float')
    expect(subject).to have_field(:units).of_type('Float!')
    expect(subject).to have_field(:applied_taxes).of_type('[FeeAppliedTax!]')
    expect(subject).to have_field(:adjusted_fee).of_type('Boolean!')
    expect(subject).to have_field(:adjusted_fee_type).of_type('AdjustedFeeTypeEnum')
    expect(subject).to have_field(:grouped_by).of_type('JSON!')

    expect(subject).to have_field(:charge_filter).of_type('ChargeFilter')
  end
end
