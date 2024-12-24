# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppliedUsageThreshold, type: :model do
  subject(:applied_usage_threshold) { build(:applied_usage_threshold) }

  it { is_expected.to belong_to(:usage_threshold) }
end
