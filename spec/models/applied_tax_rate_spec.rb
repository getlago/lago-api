# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppliedTaxRate, type: :model do
  subject(:applied_tax_rate) { create(:applied_tax_rate) }

  it_behaves_like 'paper_trail traceable'
end
