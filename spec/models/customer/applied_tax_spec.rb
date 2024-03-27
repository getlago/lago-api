# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customer::AppliedTax, type: :model do
  subject(:applied_tax) { create(:customer_applied_tax) }

  it_behaves_like "paper_trail traceable"
end
