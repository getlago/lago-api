# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCardUnit do
  subject(:unit) { build(:contract_rate_card_unit) }

  describe "associations" do
    it do
      expect(unit).to belong_to(:organization)
      expect(unit).to belong_to(:contract_rate_card).inverse_of(:units)
    end
  end

  describe "validations" do
    it "requires a nonnegative quantity and an effective date" do
      expect(unit).to validate_presence_of(:effective_date)
      expect(unit).to validate_numericality_of(:units).is_greater_than_or_equal_to(0)
    end

    context "when the organization differs from the parent card" do
      subject(:unit) do
        build(:contract_rate_card_unit, organization: other_organization, contract_rate_card:)
      end

      let(:other_organization) { create(:organization) }
      let(:contract_rate_card) { create(:contract_rate_card) }

      it "is invalid" do
        expect(unit).not_to be_valid
        expect(unit.errors.attribute_names).to include(:organization)
      end
    end

    context "when another row already exists for the card and date" do
      subject(:unit) do
        build(
          :contract_rate_card_unit,
          organization: existing_unit.organization,
          contract_rate_card: existing_unit.contract_rate_card,
          effective_date: existing_unit.effective_date
        )
      end

      let(:existing_unit) { create(:contract_rate_card_unit) }

      it "is invalid" do
        expect(unit).not_to be_valid
        expect(unit.errors.attribute_names).to include(:effective_date)
      end
    end
  end
end
