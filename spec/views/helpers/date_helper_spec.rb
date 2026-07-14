# frozen_string_literal: true

require "rails_helper"

RSpec.describe DateHelper do
  subject(:helper) { described_class }

  describe ".format" do
    it "localizes the date" do
      expect(helper.format(Date.new(2024, 1, 2))).to eq(I18n.l(Date.new(2024, 1, 2), format: :default))
    end

    it "accepts a custom format" do
      expect(helper.format(Date.new(2024, 1, 2), format: :short))
        .to eq(I18n.l(Date.new(2024, 1, 2), format: :short))
    end

    context "when the date is nil" do
      it "returns nil instead of raising" do
        expect(helper.format(nil)).to be_nil
      end
    end
  end
end
