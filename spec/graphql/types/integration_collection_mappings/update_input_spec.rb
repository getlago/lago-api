# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::IntegrationCollectionMappings::UpdateInput do
  subject { described_class }

  it { is_expected.to accept_argument(:id).of_type('ID!') }
  it { is_expected.to accept_argument(:integration_id).of_type('ID') }
  it { is_expected.to accept_argument(:mapping_type).of_type('MappingTypeEnum') }
  it { is_expected.to accept_argument(:external_account_code).of_type('String') }
  it { is_expected.to accept_argument(:external_id).of_type('String') }
  it { is_expected.to accept_argument(:external_name).of_type('String') }
  it { is_expected.to accept_argument(:tax_code).of_type('String') }
  it { is_expected.to accept_argument(:tax_nexus).of_type('String') }
  it { is_expected.to accept_argument(:tax_type).of_type('String') }
end
