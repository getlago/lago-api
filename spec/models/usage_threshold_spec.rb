# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsageThreshold, type: :model do
  subject(:usage_threshold) { build(:usage_threshold) }

  it { is_expected.to validate_numericality_of(:amount_cents).is_greater_than(0) }
end
