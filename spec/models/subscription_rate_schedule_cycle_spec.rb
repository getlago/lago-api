# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionRateScheduleCycle do
  subject { create(:subscription_rate_schedule_cycle) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:subscription_rate_schedule)
      expect(subject).to have_many(:fees).dependent(:nullify)
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_presence_of(:cycle_index)
      expect(subject).to validate_numericality_of(:cycle_index)
        .is_greater_than_or_equal_to(0)
      expect(subject).to validate_presence_of(:from_datetime)
      expect(subject).to validate_presence_of(:to_datetime)
    end
  end
end
