# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoice::AppliedTax, type: :model do
  subject(:applied_tax) { create(:invoice_applied_tax) }

  it_behaves_like "paper_trail traceable"
end
