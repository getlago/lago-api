# frozen_string_literal: true

require "rails_helper"

RSpec.describe PayableGroup, type: :model do
  subject(:payable_group) { create(:payable_group) }

  it_behaves_like "paper_trail traceable"

  it { is_expected.to have_many(:invoices) }
  it { is_expected.to have_many(:payments) }
end
