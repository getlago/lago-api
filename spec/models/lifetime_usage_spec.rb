# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LifetimeUsage, type: :model do
  subject(:lifetime_usage) { create(:lifetime_usage) }

  it { is_expected.to belong_to(:organization) }
  it { is_expected.to monetize(:current_usage_amount_cents) }
  it { is_expected.to monetize(:invoiced_usage_amount_cents) }

  describe 'default scope' do
    let(:deleted_lifetime_usage) { create(:lifetime_usage, :deleted) }

    it "only returns non-deleted lifetime-usage objects" do
      expect(LifetimeUsage.all).to eq([lifetime_usage])
      expect(LifetimeUsage.unscoped.discarded).to eq([deleted_lifetime_usage])
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

  describe 'Uniqueness constraints' do
    it "can have only 1 lifetime_usage with the same external_subscription_id within an organization" do
      expect do
        LifetimeUsage.create(organization: lifetime_usage.organization,
          external_subscripton_id: lifetime_usage.external_subscription_id)
      end.to raise_error
    end
  end

  describe "#subscription" do
    it "returns the subscription" do
      expected_subscription = Subscription.active.where(external_id: lifetime_usage.external_subscription_id).sole
      expect(lifetime_usage.subscription).to eq(expected_subscription)
    end
  end
end
