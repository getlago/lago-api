# frozen_string_literal: true

RSpec.describe Common do
  subject(:controller) { klass.new }

  let(:klass) do
    Class.new do
      include Common
      public :valid_date? # expose for testing
    end
  end

  describe "#valid_date?" do
    context "when date is nil" do
      it "returns false" do
        expect(controller.valid_date?(nil)).to be false
      end
    end

    context "when a valid date string is provided" do
      it "returns true" do
        expect(controller.valid_date?("2021-02-28")).to be true
      end
    end

    context "when an invalid date string is provided" do
      it "returns false for an impossible date" do
        expect(controller.valid_date?("2021-02-30")).to be false
      end

      it "returns false for a malformed date string" do
        expect(controller.valid_date?("not-a-date")).to be false
      end
    end
  end
end
