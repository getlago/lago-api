# frozen_string_literal: true

require "rails_helper"

RSpec.describe PendingViesCheck, type: :model do
  subject(:pending_vies_check) { build(:pending_vies_check) }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:billing_entity)
      expect(subject).to belong_to(:customer)
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_uniqueness_of(:customer_id).ignoring_case_sensitivity
      expect(subject).to validate_numericality_of(:attempts_count).is_greater_than_or_equal_to(0)
    end
  end
end
