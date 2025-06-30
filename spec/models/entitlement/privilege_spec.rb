# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entitlement::Privilege, type: :model do
  subject { build(:privilege) }

  describe "associations" do
    it do
      expect(subject).to belong_to(:organization)
      expect(subject).to belong_to(:feature).class_name("Entitlement::Feature")
    end
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:code) }
    it { is_expected.to validate_presence_of(:value_type) }
    it { is_expected.to validate_inclusion_of(:value_type).in_array(Entitlement::Privilege::VALUE_TYPES) }
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

  describe "value types" do
    it "supports integer type" do
      privilege = create(:privilege, :integer_type)
      expect(privilege.value_type).to eq("integer")
    end

    it "supports string type" do
      privilege = create(:privilege, :string_type)
      expect(privilege.value_type).to eq("string")
    end

    it "supports boolean type" do
      privilege = create(:privilege, :boolean_type)
      expect(privilege.value_type).to eq("boolean")
    end

    it "supports select type" do
      privilege = create(:privilege, :select_type)
      expect(privilege.value_type).to eq("select")
      expect(privilege.config).to include("select_options" => ["option1", "option2", "option3"])
    end
  end
end
