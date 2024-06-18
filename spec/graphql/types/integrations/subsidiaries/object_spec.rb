# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::Integrations::Subsidiaries::Object do
  subject { described_class }

  it { is_expected.to have_field(:external_id).of_type('String!') }
  it { is_expected.to have_field(:external_name).of_type('String') }
end
