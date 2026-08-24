# frozen_string_literal: true

require "rails_helper"

RSpec.describe RateCards::UpdateService do
  subject(:result) { described_class.call(rate_card:, params:) }

  let(:organization) { create(:organization) }
  let(:rate_card) { create(:rate_card, organization:, name: "Before", currency: "EUR") }

  let(:params) { {name: "After", description: "new", billing_timing: "advance"} }

  it "updates the attributes" do
    expect(result).to be_success
    expect(result.rate_card.name).to eq("After")
    expect(result.rate_card.description).to eq("new")
    expect(result.rate_card.billing_timing).to eq("advance")
  end

  describe "code editability" do
    let(:params) { {code: "after"} }

    it "updates the code when the card is not attached" do
      expect { result }.to change { rate_card.reload.code }.to("after")
    end

    it "updates the code even when the card has rates" do
      create(:rate_card_rate, organization:, rate_card:)

      expect { result }.to change { rate_card.reload.code }.to("after")
    end

    context "when the card is attached to a plan" do
      before { create(:plan_rate_card, organization:, rate_card:) }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:code]).to eq(["attached_to_plan_or_subscription"])
      end

      it "still accepts a payload resending the current code" do
        update_result = described_class.call(rate_card:, params: {name: "renamed", code: rate_card.code})

        expect(update_result).to be_success
        expect(rate_card.reload.name).to eq("renamed")
      end
    end
  end

  describe "currency" do
    it "updates the currency when the card is not attached" do
      update_result = described_class.call(rate_card:, params: {currency: "USD"})

      expect(update_result).to be_success
      expect(rate_card.reload.currency).to eq("USD")
    end

    context "when the card is attached to a plan" do
      before { create(:plan_rate_card, organization:, rate_card:) }

      it "returns a validation failure" do
        update_result = described_class.call(rate_card:, params: {currency: "USD"})

        expect(update_result).not_to be_success
        expect(update_result.error.messages[:currency]).to eq(["attached_to_plan_or_subscription"])
      end

      it "still accepts a payload resending the current currency" do
        update_result = described_class.call(rate_card:, params: {name: "renamed", currency: rate_card.currency})

        expect(update_result).to be_success
        expect(rate_card.reload.name).to eq("renamed")
      end
    end
  end

  it "produces an activity log" do
    result
    expect(Utils::ActivityLog).to have_produced("rate_card.updated").after_commit.with(rate_card)
  end

  context "when a boolean field is not a boolean" do
    let(:params) { {display_on_invoice: "hello"} }

    it "returns a validation failure instead of coercing" do
      expect(result).not_to be_success
      expect(result.error.messages[:display_on_invoice]).to eq(["value_is_invalid"])
    end
  end

  context "when the card has no rates" do
    let(:params) { {currency: "USD"} }

    it "allows changing the currency" do
      expect(result).to be_success
      expect(result.rate_card.currency).to eq("USD")
    end
  end

  context "when wallet_targetable is set without the organization feature" do
    let(:params) { {wallet_targetable: true} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:wallet_targetable]).to eq(["feature_unavailable"])
    end
  end

  context "when applied_pricing_unit_code is unknown" do
    let(:params) { {applied_pricing_unit_code: "unknown"} }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:applied_pricing_unit_code]).to eq(["value_is_invalid"])
    end
  end

  context "when the card has rates" do
    before { create(:rate_card_rate, organization:, rate_card:) }

    context "when changing the currency" do
      let(:params) { {currency: "USD"} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:currency]).to eq(["not_editable_with_rates"])
      end
    end

    context "when sending the unchanged currency" do
      let(:params) { {currency: "EUR", name: "After"} }

      it "is allowed" do
        expect(result).to be_success
        expect(result.rate_card.name).to eq("After")
      end
    end

    context "when changing the billing_timing" do
      let(:params) { {billing_timing: "advance"} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:billing_timing]).to eq(["not_editable_with_rates"])
      end
    end

    context "when changing the proration" do
      let(:params) { {proration: true} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:proration]).to eq(["not_editable_with_rates"])
      end
    end

    context "when changing regroup_paid_fees" do
      let(:params) { {regroup_paid_fees: "invoice"} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:regroup_paid_fees]).to eq(["not_editable_with_rates"])
      end
    end

    context "when sending an explicit null regroup_paid_fees" do
      let(:params) { {regroup_paid_fees: nil, name: "After"} }

      it "reads as none, not as a locked-field change" do
        expect(result).to be_success
        expect(result.rate_card.name).to eq("After")
        expect(result.rate_card.regroup_paid_fees).to eq("none")
      end
    end

    context "when resending all unchanged billing fields" do
      let(:params) do
        {
          currency: rate_card.currency,
          billing_timing: rate_card.billing_timing,
          proration: rate_card.proration,
          regroup_paid_fees: rate_card.regroup_paid_fees,
          name: "After"
        }
      end

      it "is allowed" do
        expect(result).to be_success
        expect(result.rate_card.name).to eq("After")
      end
    end

    context "when changing display_on_invoice" do
      let(:params) { {display_on_invoice: false} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:display_on_invoice]).to eq(["not_editable_with_rates"])
      end
    end

    context "when changing wallet_targetable" do
      let(:params) { {wallet_targetable: false} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:wallet_targetable]).to eq(["not_editable_with_rates"])
      end
    end

    context "when editing presentation fields" do
      let(:params) { {name: "After", description: "new"} }

      it "is allowed" do
        expect(result).to be_success
        expect(result.rate_card.name).to eq("After")
      end
    end
  end

  describe "taxes" do
    let(:tax1) { create(:tax, organization:) }
    let(:tax2) { create(:tax, organization:) }
    let(:params) { {tax_codes: [tax2.code]} }

    before { create(:rate_card_applied_tax, rate_card:, tax: tax1, organization:) }

    it "replaces the rate card taxes" do
      expect(result).to be_success
      expect(result.rate_card.taxes).to eq([tax2])
    end

    context "when tax codes are empty" do
      let(:params) { {tax_codes: []} }

      it "removes the rate card tax override" do
        expect(result).to be_success
        expect(result.rate_card.taxes).to be_empty
      end
    end

    context "when tax codes are null" do
      let(:params) { {tax_codes: nil} }

      it "keeps the existing taxes" do
        expect(result).to be_success
        expect(result.rate_card.taxes).to eq([tax1])
      end
    end

    context "when tax codes are omitted" do
      let(:params) { {name: "Renamed"} }

      it "keeps the existing taxes" do
        expect(result).to be_success
        expect(result.rate_card.taxes).to eq([tax1])
      end
    end

    context "when the rate card is attached to a subscription" do
      before { create(:subscription_rate_card, organization:, rate_card:) }

      it "still updates the taxes" do
        expect(result).to be_success
        expect(result.rate_card.taxes).to eq([tax2])
      end
    end

    context "when a tax belongs to another organization" do
      let(:other_tax) { create(:tax) }
      let(:params) { {name: "Should roll back", tax_codes: [other_tax.code]} }

      it "returns a tax not found failure and rolls back other changes" do
        expect(result).to be_a(described_class::Result)
        expect(result).not_to be_success
        expect(result.error.resource).to eq("tax")
        expect(rate_card.reload.name).to eq("Before")
        expect(rate_card.taxes).to eq([tax1])
      end
    end
  end

  context "when rate_card is nil" do
    let(:rate_card) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("rate_card")
    end
  end
end
