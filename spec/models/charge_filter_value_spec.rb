# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChargeFilterValue, type: :model do
  subject { build(:charge_filter_value) }

  it_behaves_like 'paper_trail traceable'

  it { is_expected.to belong_to(:charge_filter) }
  it { is_expected.to belong_to(:billable_metric_filter) }

  it { is_expected.to validate_presence_of(:value) }
end
