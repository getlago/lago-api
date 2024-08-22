# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LifetimeUsage, type: :model do
  subject(:lifetime_usage) { create(:lifetime_usage) }

  it { is_expected.to belong_to(:organization) }

  describe 'default scope' do
    let!(:deleted_lifetime_usage) { create(:lifetime_usage, :deleted) }

    it "only returns non-deleted lifetime-usage objects" do
      expect(described_class.all).to eq([lifetime_usage])
      expect(described_class.unscoped.discarded).to eq([deleted_lifetime_usage])
    end
  end

  describe 'Validations' do
    it 'requires that current_usage_amount_cents is postive' do
      lifetime_usage.current_usage_amount_cents = -1
      expect(lifetime_usage).not_to be_valid

      lifetime_usage.current_usage_amount_cents = 1
      expect(lifetime_usage).to be_valid
    end

    it 'requires that invoiced_usage_amount_cents is postive' do
      lifetime_usage.invoiced_usage_amount_cents = -1
      expect(lifetime_usage).not_to be_valid

      lifetime_usage.invoiced_usage_amount_cents = 1
      expect(lifetime_usage).to be_valid
    end

    it 'requires that historical_usage_amount_cents is positive' do
      lifetime_usage.historical_usage_amount_cents = -1
      expect(lifetime_usage).not_to be_valid

      lifetime_usage.historical_usage_amount_cents = 0
      expect(lifetime_usage).to be_valid

      lifetime_usage.historical_usage_amount_cents = 1
      expect(lifetime_usage).to be_valid
    end
  end

  describe ".needs_recalculation scope" do
    let(:lifetime_usage1) { create(:lifetime_usage, recalculate_invoiced_usage: true) }
    let(:lifetime_usage2) { create(:lifetime_usage, recalculate_current_usage: true) }
    let(:lifetime_usage3) { create(:lifetime_usage, recalculate_invoiced_usage: false, recalculate_current_usage: false) }

    before do
      lifetime_usage1
      lifetime_usage2
      lifetime_usage3
    end

    it "returns only the lifetime_usages with a recalculate flag set" do
      expect(described_class.needs_recalculation).to match_array([lifetime_usage1, lifetime_usage2])
    end
  end
end
