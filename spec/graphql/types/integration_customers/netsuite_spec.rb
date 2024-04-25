# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::IntegrationCustomers::Netsuite do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID!') }
  it { is_expected.to have_field(:external_customer_id).of_type('String') }
  it { is_expected.to have_field(:subsidiary_id).of_type('String') }
  it { is_expected.to have_field(:sync_with_provider).of_type('Boolean') }
end
