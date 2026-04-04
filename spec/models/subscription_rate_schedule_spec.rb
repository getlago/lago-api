# frozen_string_literal: true

require "rails_helper"

RSpec.describe SubscriptionRateSchedule do
  subject { create(:subscription_rate_schedule) }

  it_behaves_like "paper_trail traceable"

  describe "enums" do
    it do
      expect(subject).to define_enum_for(:status)
        .backed_by_column_of_type(:enum)
        .validating
        .with_values(pending: "pending", active: "active", terminated: "terminated")
    end
  end

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:subscription)
      expect(subject).to belong_to(:product_item)
      expect(subject).to belong_to(:rate_schedule)
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_numericality_of(:intervals_billed)
        .is_greater_than_or_equal_to(0)
    end
  end
end
