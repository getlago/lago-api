# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::IntegrationMappings::Netsuite::Object do
  subject { described_class }

  it { is_expected.to have_field(:id).of_type('ID!') }
  it { is_expected.to have_field(:integration_id).of_type('ID!') }
  it { is_expected.to have_field(:mappable_id).of_type('ID!') }
  it { is_expected.to have_field(:mappable_type).of_type('NetsuiteMappableTypeEnum!') }
  it { is_expected.to have_field(:netsuite_account_code).of_type('String!') }
  it { is_expected.to have_field(:netsuite_id).of_type('String!') }
  it { is_expected.to have_field(:netsuite_name).of_type('String') }
end
