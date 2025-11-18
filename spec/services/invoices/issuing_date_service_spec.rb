# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::IssuingDateService do
  subject(:issuing_date_service) { described_class.new(customer:, recurring:) }

  let(:customer) do
    build(
      :customer,
      subscription_invoice_issuing_date_anchor:,
      subscription_invoice_issuing_date_adjustment:,
      invoice_grace_period: 3
    )
  end

  let(:subscription_invoice_issuing_date_anchor) { "current_period_end" }
  let(:subscription_invoice_issuing_date_adjustment) { "keep_anchor" }

  describe "#base_date" do
    let(:base_date) { issuing_date_service.base_date(timestamp) }
    let(:timestamp) { Time.zone.parse("05 May 2025") }

    context "when recurring = true" do
      let(:recurring) { true }

      context "with current_period_end" do
        let(:subscription_invoice_issuing_date_anchor) { "current_period_end" }

        it "returns the current billing period end date" do
          expect(base_date.to_s).to eq("2025-05-04")
        end
      end

      context "with next_period_start" do
        let(:subscription_invoice_issuing_date_anchor) { "next_period_start" }

        it "returns the next billing period start date" do
          expect(base_date.to_s).to eq("2025-05-05")
        end
      end

      context "with no preferences set on the customer level " do
        let(:billing_entity) do
          build(
            :billing_entity,
            subscription_invoice_issuing_date_anchor: "current_period_end",
            subscription_invoice_issuing_date_adjustment: "keep_anchor",
            invoice_grace_period: 3
          )
        end

        let(:customer) { build(:customer, billing_entity:) }

        it "returns a date based on billing entity settings" do
          expect(base_date.to_s).to eq("2025-05-04")
        end
      end
    end

    context "when recurring = false" do
      let(:recurring) { false }

      it "ignores all issuing date preferences" do
        expect(base_date.to_s).to eq("2025-05-05")
      end
    end
  end

  describe "#grace_period" do
    context "when recurring = true" do
      let(:recurring) { true }

      context "with current_period_end + keep_anchor" do
        let(:subscription_invoice_issuing_date_anchor) { "current_period_end" }
        let(:subscription_invoice_issuing_date_adjustment) { "keep_anchor" }

        it "returns 0" do
          expect(issuing_date_service.grace_period).to eq(0)
        end
      end

      context "with current_period_end + align_with_finalization_date" do
        let(:subscription_invoice_issuing_date_anchor) { "current_period_end" }
        let(:subscription_invoice_issuing_date_adjustment) { "align_with_finalization_date" }

        it "returns invoice_grace_period adjustd for current period end" do
          expect(issuing_date_service.grace_period).to eq(4)
        end
      end

      context "with next_period_start + keep_anchor" do
        let(:subscription_invoice_issuing_date_anchor) { "next_period_start" }
        let(:subscription_invoice_issuing_date_adjustment) { "keep_anchor" }

        it "returns 0" do
          expect(issuing_date_service.grace_period).to eq(0)
        end
      end

      context "with next_period_start + align_with_finalization_date" do
        let(:subscription_invoice_issuing_date_anchor) { "next_period_start" }
        let(:subscription_invoice_issuing_date_adjustment) { "align_with_finalization_date" }

        it "returns invoice_grace_period" do
          expect(issuing_date_service.grace_period).to eq(3)
        end
      end

      context "with no preferences set on the customer level " do
        let(:billing_entity) do
          build(
            :billing_entity,
            subscription_invoice_issuing_date_anchor: "current_period_end",
            subscription_invoice_issuing_date_adjustment: "keep_anchor",
            invoice_grace_period: 3
          )
        end

        let(:customer) { build(:customer, billing_entity:) }

        it "returns grace period based on billing entity settings" do
          expect(issuing_date_service.grace_period).to eq(0)
        end
      end
    end

    context "when recurring = false" do
      let(:recurring) { false }

      it "returns invoice_grace_period" do
        expect(issuing_date_service.grace_period).to eq(3)
      end
    end
  end

  describe "#grace_period_diff" do
    let(:grace_period_diff) { issuing_date_service.grace_period_diff(1) }

    context "when recurring = true" do
      let(:recurring) { true }

      context "with current_period_end + keep_anchor" do
        let(:subscription_invoice_issuing_date_anchor) { "current_period_end" }
        let(:subscription_invoice_issuing_date_adjustment) { "keep_anchor" }

        it "returns 0" do
          expect(grace_period_diff).to eq(0)
        end
      end

      context "with current_period_end + align_with_finalization_date" do
        let(:subscription_invoice_issuing_date_anchor) { "current_period_end" }
        let(:subscription_invoice_issuing_date_adjustment) { "align_with_finalization_date" }

        it "returns diff between grace periods" do
          expect(grace_period_diff).to eq(2)
        end
      end

      context "with next_period_start + keep_anchor" do
        let(:subscription_invoice_issuing_date_anchor) { "next_period_start" }
        let(:subscription_invoice_issuing_date_adjustment) { "keep_anchor" }

        it "returns 0" do
          expect(grace_period_diff).to eq(0)
        end
      end

      context "with next_period_start + align_with_finalization_date" do
        let(:subscription_invoice_issuing_date_anchor) { "next_period_start" }
        let(:subscription_invoice_issuing_date_adjustment) { "align_with_finalization_date" }

        it "returns diff between grace periods" do
          expect(grace_period_diff).to eq(2)
        end
      end

      context "with no preferences set on the customer level " do
        let(:billing_entity) do
          build(
            :billing_entity,
            subscription_invoice_issuing_date_anchor: "current_period_end",
            subscription_invoice_issuing_date_adjustment: "keep_anchor",
            invoice_grace_period: 3
          )
        end

        let(:customer) { build(:customer, billing_entity:) }

        it "returns grace period diff based on billing entity settings" do
          expect(grace_period_diff).to eq(0)
        end
      end
    end

    context "when recurring = false" do
      let(:recurring) { false }

      it "returns the diff between grace periods" do
        expect(grace_period_diff).to eq(2)
      end
    end
  end
end
