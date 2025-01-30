# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::AdjustedFees::CreateInput do
  subject { described_class }

  it { is_expected.to accept_argument(:invoice_id).of_type('ID!') }
  it { is_expected.to accept_argument(:fee_id).of_type('ID') }
  it { is_expected.to accept_argument(:charge_id).of_type('ID') }
  it { is_expected.to accept_argument(:charge_filter_id).of_type('ID') }
  it { is_expected.to accept_argument(:subscription_id).of_type('ID') }
  it { is_expected.to accept_argument(:invoice_display_name).of_type('String') }
  it { is_expected.to accept_argument(:unit_precise_amount).of_type('String') }
  it { is_expected.to accept_argument(:units).of_type('Float') }
end
