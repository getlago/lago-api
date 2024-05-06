# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::IntegrationCustomers::Input do
  subject { described_class }

  it { is_expected.to accept_argument(:external_customer_id).of_type('String') }
  it { is_expected.to accept_argument(:integration).of_type('IntegrationTypeEnum') }
  it { is_expected.to accept_argument(:integration_code).of_type('String') }
  it { is_expected.to accept_argument(:subsidiary_id).of_type('String') }
  it { is_expected.to accept_argument(:sync_with_provider).of_type('Boolean') }
end
