# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::IntegrationItems::Object do
  subject { described_class }

  it { is_expected.to have_field(:account_code).of_type('String') }
  it { is_expected.to have_field(:external_id).of_type('String!') }
  it { is_expected.to have_field(:id).of_type('ID!') }
  it { is_expected.to have_field(:integration_id).of_type('ID!') }
  it { is_expected.to have_field(:item_type).of_type('IntegrationItemTypeEnum!') }
  it { is_expected.to have_field(:name).of_type('String') }
end
