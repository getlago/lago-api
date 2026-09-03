# frozen_string_literal: true

RSpec.describe Charge::AppliedTax do
  subject(:charge_applied_tax) { create(:charge_applied_tax) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:billable_metric) { create_default(:billable_metric) }
  let_it_be(:plan) { create_default(:plan) }

  it { is_expected.to belong_to(:charge) }
  it { is_expected.to belong_to(:tax) }
  it { is_expected.to belong_to(:organization) }
end
