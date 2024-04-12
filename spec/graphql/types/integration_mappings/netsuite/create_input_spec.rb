# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::IntegrationMappings::Netsuite::CreateInput do
  subject { described_class }

  it { is_expected.to accept_argument(:mappable_id).of_type('ID!') }
  it { is_expected.to accept_argument(:mappable_type).of_type('NetsuiteMappableTypeEnum!') }
  it { is_expected.to accept_argument(:netsuite_account_code).of_type('String!') }
  it { is_expected.to accept_argument(:netsuite_id).of_type('String!') }
  it { is_expected.to accept_argument(:netsuite_name).of_type('String') }
end
