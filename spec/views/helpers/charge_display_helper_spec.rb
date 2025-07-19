# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChargeDisplayHelper do
  subject(:helper) { described_class }

  describe ".format_min_amount" do
    subject { helper.format_min_amount(charge) }

    let(:plan) { create(:plan, amount_currency: "USD") }
    let(:charge) { create(:standard_charge, plan:, min_amount_cents: 500) }

    it "returns the min amount with the appropriate currency symbol" do
      expect(subject).to eq "$5.00"
    end
  end
end
