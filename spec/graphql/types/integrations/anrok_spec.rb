# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Integrations::Anrok do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID!') }

  it { is_expected.to have_field(:api_key).of_type('String!') }
  it { is_expected.to have_field(:code).of_type('String!') }
  it { is_expected.to have_field(:failed_invoices_count).of_type('Integer') }
  it { is_expected.to have_field(:has_mappings_configured).of_type('Boolean') }
  it { is_expected.to have_field(:name).of_type('String!') }
  it { is_expected.to have_field(:external_account_id).of_type('String') }
end
