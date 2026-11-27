# frozen_string_literal: true

require "rails_helper"

RSpec.describe ContractRateCardTerm do
  subject(:unit) { build(:contract_rate_card_term) }

  describe "enums" do
    it do
      expect(unit).to define_enum_for(:application_timing)
        .backed_by_column_of_type(:enum)
        .with_values(current_billing_cycle: "current_billing_cycle", next_billing_cycle: "next_billing_cycle")
        .with_default(:current_billing_cycle)
        .validating(allowing_nil: false)
    end
  end

  describe "associations" do
    it do
      expect(unit).to belong_to(:organization)
      expect(unit).to belong_to(:contract_rate_card).inverse_of(:terms)
    end
  end

  describe "validations" do
    it "requires a nonnegative quantity and an effective date" do
      expect(unit).to validate_presence_of(:effective_date)
      expect(unit).to validate_numericality_of(:units).is_greater_than_or_equal_to(0)
    end

    context "when the organization differs from the parent card" do
      subject(:unit) do
        build(:contract_rate_card_term, organization: other_organization, contract_rate_card:)
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
          :contract_rate_card_term,
          organization: existing_unit.organization,
          contract_rate_card: existing_unit.contract_rate_card,
          effective_date: existing_unit.effective_date
        )
      end

      let(:existing_unit) { create(:contract_rate_card_term) }

      it "is invalid" do
        expect(unit).not_to be_valid
        expect(unit.errors.attribute_names).to include(:effective_date)
      end
    end
  end

  it "allows scheduled terms to share a request date with starting and previously applied units" do
    starting = create(:contract_rate_card_term)
    2.times do
      create(:contract_rate_card_term, organization: starting.organization, contract_rate_card: starting.contract_rate_card,
        effective_date: starting.effective_date, application_timing: :next_billing_cycle)
    end
    expect(starting.contract_rate_card.terms.count).to eq(3)
  end

  describe "application_timing persistence" do
    let(:unit) { create(:contract_rate_card_term, application_timing: :next_billing_cycle) }

    it "persists next_billing_cycle" do
      expect(unit.reload.application_timing).to eq("next_billing_cycle")
    end

    context "when no timing is supplied" do
      let(:unit) { create(:contract_rate_card_term) }

      it "persists the default timing" do
        expect(unit.reload.application_timing).to eq("current_billing_cycle")
      end
    end

    context "with an invalid timing" do
      let(:unit) { build(:contract_rate_card_term, application_timing: "invalid") }

      it "rejects the value" do
        expect(unit).not_to be_valid
        expect(unit.errors.attribute_names).to include(:application_timing)
      end
    end
  end

  describe "#starts_at" do
    let(:customer) { build(:customer, timezone: "America/New_York") }
    let(:contract) { build(:contract, customer:) }
    let(:card) { build(:contract_rate_card, contract:) }
    let(:term) { build(:contract_rate_card_term, contract_rate_card: card, effective_date: Date.new(2026, 9, 1)) }

    it "starts at midnight in the customer timezone" do
      expect(term.starts_at).to eq(Time.utc(2026, 9, 1, 4))
    end
  end
end
