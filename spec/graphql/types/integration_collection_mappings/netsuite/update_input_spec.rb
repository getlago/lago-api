# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::IntegrationCollectionMappings::Netsuite::UpdateInput do
  subject { described_class }

  it { is_expected.to accept_argument(:netsuite_account_code).of_type('String') }
  it { is_expected.to accept_argument(:netsuite_id).of_type('String') }
  it { is_expected.to accept_argument(:netsuite_name).of_type('String') }
end
