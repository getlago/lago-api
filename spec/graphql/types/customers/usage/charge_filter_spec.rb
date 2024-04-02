# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Customers::Usage::ChargeFilter do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID') }
  it { is_expected.to have_field(:amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:events_count).of_type('Int!') }
  it { is_expected.to have_field(:invoice_display_name).of_type('String') }
  it { is_expected.to have_field(:units).of_type('Float!') }
  it { is_expected.to have_field(:values).of_type('ChargeFilterValues!') }
end
