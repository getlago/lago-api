# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payment, type: :model do
  subject(:payment) { create(:payment) }

  it_behaves_like "paper_trail traceable"
end
