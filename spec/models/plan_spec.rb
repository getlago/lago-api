# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plan, type: :model do
  describe '.has_trial?' do
    let(:plan) { create(:plan, trial_period: 3) }

    it 'returns true when trial_period' do
      expect(plan).to have_trial
    end
  end
end
