# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppliedUsageThreshold, type: :model do
  subject(:applied_usage_threshold) { build(:applied_usage_threshold) }

  it { is_expected.to belong_to(:usage_threshold) }
  it { is_expected.to belong_to(:invoice) }

  it { is_expected.to validate_uniqueness_of(:usage_threshold_id).scoped_to(:invoice_id).case_insensitive }
end
