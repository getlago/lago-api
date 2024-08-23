# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppliedUsageThreshold, type: :model do
  subject(:applied_usage_threshold) { create(:applied_usage_threshold, invoice:) }

  let(:invoice) { create(:invoice) }

  it { is_expected.to belong_to(:usage_threshold) }
end
