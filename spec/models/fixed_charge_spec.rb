# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharge, type: :model do
  subject { build(:fixed_charge) }

  it_behaves_like "paper_trail traceable"

  it { expect(described_class).to be_soft_deletable }
  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:plan) }
  it { is_expected.to belong_to(:add_on) }
  it { is_expected.to belong_to(:parent).class_name("FixedCharge").optional }
  it { is_expected.to have_many(:children).class_name("FixedCharge").dependent(:nullify) }

  it { is_expected.to validate_numericality_of(:units).is_greater_than_or_equal_to(0) }
  it { is_expected.to validate_presence_of(:charge_model) }
  it { is_expected.to validate_inclusion_of(:pay_in_advance).in_array([true, false]) }
  it { is_expected.to validate_inclusion_of(:prorated).in_array([true, false]) }
  it { is_expected.to validate_presence_of(:properties) }
end
