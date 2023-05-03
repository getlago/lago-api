# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TaxRate, type: :model do
  subject(:tax_rate) { build(:tax_rate) }

  it_behaves_like 'paper_trail traceable'
end
