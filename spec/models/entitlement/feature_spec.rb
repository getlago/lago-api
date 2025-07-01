# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::Feature, type: :model do
  subject { build(:feature) }

  it { expect(described_class).to be_soft_deletable }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to have_many(:privileges).class_name("Entitlement::Privilege").dependent(:destroy)
    end
  end

  describe "validations" do
    it do
      expect(subject).to validate_presence_of(:code)
      expect(subject).to validate_length_of(:code).is_at_most(255)
      expect(subject).to validate_length_of(:name).is_at_most(255)
      expect(subject).to validate_length_of(:description).is_at_most(255)
    end
  end
end
