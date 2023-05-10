# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CustomersTaxRate, type: :model do
  subject(:customers_tax_rate) { create(:customers_tax_rate) }

  it_behaves_like 'paper_trail traceable'
end
