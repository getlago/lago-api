# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppliedTax, type: :model do
  subject(:applied_tax) { create(:applied_tax) }

  it_behaves_like 'paper_trail traceable'
end
