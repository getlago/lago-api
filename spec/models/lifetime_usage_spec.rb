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
  end
end
