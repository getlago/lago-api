# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Commitments::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID!') }
  it { is_expected.to have_field(:amount_cents).of_type('BigInt!') }
  it { is_expected.to have_field(:commitment_type).of_type('CommitmentTypeEnum!') }
  it { is_expected.to have_field(:invoice_display_name).of_type('String') }
  it { is_expected.to have_field(:plan).of_type('Plan!') }
  it { is_expected.to have_field(:taxes).of_type('[Tax!]') }
  it { is_expected.to have_field(:created_at).of_type('ISO8601DateTime!') }
  it { is_expected.to have_field(:updated_at).of_type('ISO8601DateTime!') }
end
