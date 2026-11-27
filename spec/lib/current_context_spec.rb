# frozen_string_literal: true

require "rails_helper"

RSpec.describe CurrentContext do
  describe ".membership_id" do
    after { described_class.reset }

    it "reads the id of the membership" do
      described_class.membership = "membership/abc"

      expect(described_class.membership_id).to eq("abc")
    end
  end

  describe ".membership_id=" do
    after { described_class.reset }

    it "sets the membership as audit trails read it" do
      described_class.membership_id = "abc"

      expect(described_class.membership).to eq("membership/abc")
    end

    it "clears the membership without an id" do
      described_class.membership = "membership/abc"
      described_class.membership_id = nil

      expect(described_class.membership).to be_nil
    end

    it "is accepted by set" do
      described_class.set(membership_id: "abc") do
        expect(described_class.membership).to eq("membership/abc")
      end
    end
  end
end
