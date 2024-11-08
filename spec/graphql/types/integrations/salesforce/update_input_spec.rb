# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Integrations::Salesforce::UpdateInput do
  subject { described_class }

  it { is_expected.to accept_argument(:id).of_type('ID') }
  it { is_expected.to accept_argument(:name).of_type('String') }
  it { is_expected.to accept_argument(:instance_id).of_type('String') }
end
