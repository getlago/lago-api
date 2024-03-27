# frozen_string_literal: true

require "rails_helper"

RSpec.describe AppliedAddOn, type: :model do
  subject(:applied_add_on) { create(:applied_add_on) }

  it_behaves_like "paper_trail traceable"
end
