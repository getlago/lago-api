# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customer::AppliedTax do
  subject(:applied_tax) { create(:customer_applied_tax) }

  let_it_be(:organization) { create_default(:organization) }
  let_it_be(:customer) { create_default(:customer) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to belong_to(:organization) }
end
