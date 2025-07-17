# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionFixedChargeUnitsOverride, type: :model do
  subject { build(:subscription_fixed_charge_units_override) }
  it_behaves_like "paper_trail traceable"

  it_behaves_like "paper_trail traceable"

  it { expect(described_class).to be_soft_deletable }
  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:billing_entity) }
  it { is_expected.to belong_to(:subscription) }
  it { is_expected.to belong_to(:fixed_charge) }

  describe "validations" do
    it { is_expected.to validate_presence_of(:units) }
    it { is_expected.to validate_numericality_of(:units).is_greater_than_or_equal_to(0) }
  end
end
