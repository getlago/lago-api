# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FeesTax, type: :model do
  subject(:fees_tax) { create(:fees_tax) }

  it_behaves_like 'paper_trail traceable'
end
