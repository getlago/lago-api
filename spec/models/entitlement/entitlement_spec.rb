# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::Entitlement, type: :model do
  subject { build(:entitlement) }

  it { expect(described_class).to be_soft_deletable }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:feature).class_name("Entitlement::Feature")
      expect(subject).to belong_to(:plan)
      expect(subject).to have_many(:values).class_name("Entitlement::EntitlementValue").dependent(:destroy)
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_presence_of(:entitlement_feature_id)
      expect(subject).to validate_presence_of(:plan_id)
    end
  end
end
