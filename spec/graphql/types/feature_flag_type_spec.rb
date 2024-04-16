# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Types::FeatureFlagType do
  subject(:ff_type) { described_class }

  it { expect(ff_type.fields.keys).to match_array(FeatureFlag::FEATURES.keys) }
end
