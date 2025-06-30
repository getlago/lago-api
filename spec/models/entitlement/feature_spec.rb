# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::Feature, type: :model do
  subject { build(:feature) }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to have_many(:privileges).class_name("Entitlement::Privilege").dependent(:destroy)
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:code) }
  end

  describe "soft deletion" do
    it "can be discarded and undiscarded" do
      expect(subject.discarded?).to be(false)

      subject.discard
      expect(subject.discarded?).to be(true)
      expect(subject.deleted_at).not_to be_nil

      subject.undiscard
      expect(subject.discarded?).to be(false)
      expect(subject.deleted_at).to be_nil
    end
  end
end
