# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::IntegrationCustomers::Input do
  subject { described_class }

  it { is_expected.to accept_argument(:id).of_type('ID') }
  it { is_expected.to accept_argument(:external_customer_id).of_type('String') }
  it { is_expected.to accept_argument(:integration_type).of_type('IntegrationTypeEnum') }
  it { is_expected.to accept_argument(:integration_id).of_type('ID') }
  it { is_expected.to accept_argument(:integration_code).of_type('String') }
  it { is_expected.to accept_argument(:subsidiary_id).of_type('String') }
  it { is_expected.to accept_argument(:sync_with_provider).of_type('Boolean') }
  it { is_expected.to accept_argument(:targeted_object).of_type('HubspotTargetedObjectsEnum') }
end
