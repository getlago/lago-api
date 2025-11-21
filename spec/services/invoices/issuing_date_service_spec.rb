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

  describe "#grace_period_adjustment" do
    context "when recurring = true" do
      let(:recurring) { true }

      context "with current_period_end + keep_anchor" do
        let(:subscription_invoice_issuing_date_anchor) { "current_period_end" }
        let(:subscription_invoice_issuing_date_adjustment) { "keep_anchor" }

        it "returns -1" do
          expect(issuing_date_service.grace_period_adjustment).to eq(-1)
        end
      end

      context "with current_period_end + align_with_finalization_date" do
        let(:subscription_invoice_issuing_date_anchor) { "current_period_end" }
        let(:subscription_invoice_issuing_date_adjustment) { "align_with_finalization_date" }

        it "returns grace_period" do
          expect(issuing_date_service.grace_period_adjustment).to eq(3)
        end
      end

      context "with next_period_start + keep_anchor" do
        let(:subscription_invoice_issuing_date_anchor) { "next_period_start" }
        let(:subscription_invoice_issuing_date_adjustment) { "keep_anchor" }

        it "returns 0" do
          expect(issuing_date_service.grace_period_adjustment).to eq(0)
        end
      end

      context "with next_period_start + align_with_finalization_date" do
        let(:subscription_invoice_issuing_date_anchor) { "next_period_start" }
        let(:subscription_invoice_issuing_date_adjustment) { "align_with_finalization_date" }

        it "returns grace_period" do
          expect(issuing_date_service.grace_period_adjustment).to eq(3)
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

        it "returns value based on billing entity settings" do
          expect(issuing_date_service.grace_period_adjustment).to eq(-1)
        end
      end
    end

    context "when recurring = false" do
      let(:recurring) { false }

      it "returns invoice_grace_period" do
        expect(issuing_date_service.grace_period_adjustment).to eq(3)
      end
    end
  end
end
