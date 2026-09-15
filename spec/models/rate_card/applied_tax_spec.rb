# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCard::AppliedTax do
  subject(:applied_tax) { build(:rate_card_applied_tax) }

  it_behaves_like "paper_trail traceable"

  describe "associations" do
    it do
      expect(applied_tax).to belong_to(:rate_card)
      expect(applied_tax).to belong_to(:tax)
      expect(applied_tax).to belong_to(:organization)
    end
  end
end
