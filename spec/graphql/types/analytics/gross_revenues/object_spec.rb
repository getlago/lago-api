# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Analytics::GrossRevenues::Object do
  subject { described_class }

  it { is_expected.to have_field(:month).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:amount_cents).of_type('BigInt') }
  it { is_expected.to have_field(:currency).of_type('CurrencyEnum') }
end
