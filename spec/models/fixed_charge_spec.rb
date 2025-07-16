# frozen_string_literal: true

require "rails_helper"

RSpec.describe FixedCharge, type: :model do
  it { is_expected.to belong_to(:organization) }
  it { is_expected.to belong_to(:plan) }
  it { is_expected.to belong_to(:add_on) }
  it { is_expected.to belong_to(:parent).optional }

  it { is_expected.to validate_numericality_of(:units).is_greater_than_or_equal_to(0) }
end
