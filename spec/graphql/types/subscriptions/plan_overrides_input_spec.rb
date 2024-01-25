# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Subscriptions::PlanOverridesInput do
  subject { described_class }

  it { is_expected.to accept_argument(:amount_cents).of_type('BigInt') }
  it { is_expected.to accept_argument(:amount_currency).of_type('CurrencyEnum') }
  it { is_expected.to accept_argument(:charges).of_type('[ChargeOverridesInput!]') }
  it { is_expected.to accept_argument(:description).of_type('String') }
  it { is_expected.to accept_argument(:minimum_commitment).of_type('CommitmentInput') }
  it { is_expected.to accept_argument(:invoice_display_name).of_type('String') }
  it { is_expected.to accept_argument(:name).of_type('String') }
  it { is_expected.to accept_argument(:tax_codes).of_type('[String!]') }
  it { is_expected.to accept_argument(:trial_period).of_type('Float') }
end
