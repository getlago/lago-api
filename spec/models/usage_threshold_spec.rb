# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsageThreshold, type: :model do
  subject(:usage_threshold) { build(:usage_threshold) }

  it { is_expected.to validate_numericality_of(:amount_cents).is_greater_than(0) }

  describe 'default scope' do
    let!(:deleted_usage_threshold) { create(:usage_threshold, :deleted) }

    it "only returns non-deleted usage_threshold objects" do
      expect(described_class.all).to eq([])
      expect(described_class.unscoped.discarded).to eq([deleted_usage_threshold])
    end
  end
end
