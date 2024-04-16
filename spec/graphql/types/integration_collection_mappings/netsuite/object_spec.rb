# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::IntegrationCollectionMappings::Netsuite::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID!') }
  it { is_expected.to have_field(:integration_id).of_type('ID!') }
  it { is_expected.to have_field(:mapping_type).of_type('NetsuiteMappingTypeEnum!') }
  it { is_expected.to have_field(:netsuite_account_code).of_type('String!') }
  it { is_expected.to have_field(:netsuite_id).of_type('String!') }
  it { is_expected.to have_field(:netsuite_name).of_type('String') }
end
