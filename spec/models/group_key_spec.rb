# frozen_string_literal: true

require "rails_helper"

RSpec.describe GroupKey do
  subject(:group_key) { build(:group_key) }

  describe "enums" do
    it do
      expect(subject)
        .to define_enum_for(:key_type)
        .backed_by_column_of_type(:enum)
        .with_values(pricing: "pricing", presentation: "presentation")
    end
  end

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:charge)
      expect(subject).to belong_to(:charge_filter).optional
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_presence_of(:key)
      expect(subject).to validate_presence_of(:key_type)
    end
  end
end
