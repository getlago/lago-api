# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsageTreshold, type: :model do
  subject(:usage_treshold) { build(:usage_treshold) }

  it { is_expected.to belong_to(:plan) }

  it { is_expected.to validate_inclusion_of(:amount_currency).in_array(Currencies::ACCEPTED_CURRENCIES.keys) }
  it { is_expected.to validate_numericality_of(:amount_cents).is_greater_than(0) }
  it { is_expected.to validate_uniqueness_of(:amount_cents).scoped_to(%i[plan_id recurring]) }
  it { is_expected.to validate_uniqueness_of(:recurring).scoped_to(:plan_id) }
end
