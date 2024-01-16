# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChargeFilter, type: :model do
  subject(:charge_filter) { build(:charge_filter) }

  it_behaves_like 'paper_trail traceable'

  it { is_expected.to belong_to(:charge) }
  it { is_expected.to have_many(:values).dependent(:destroy) }
  it { is_expected.to have_many(:fees) }
end
