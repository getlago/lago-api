# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Integrations::Xero do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID!') }

  it { is_expected.to have_field(:code).of_type('String!') }
  it { is_expected.to have_field(:connection_id).of_type('ID!') }
  it { is_expected.to have_field(:has_mappings_configured).of_type('Boolean') }
  it { is_expected.to have_field(:name).of_type('String!') }

  it { is_expected.to have_field(:sync_credit_notes).of_type('Boolean') }
  it { is_expected.to have_field(:sync_invoices).of_type('Boolean') }
  it { is_expected.to have_field(:sync_payments).of_type('Boolean') }
end
