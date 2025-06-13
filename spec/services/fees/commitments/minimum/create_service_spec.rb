# frozen_string_literal: true

require "rails_helper"

RSpec.describe Fees::Commitments::Minimum::CreateService do
  subject(:service_call) { described_class.call(invoice_subscription:) }

  let(:invoice) { create(:invoice, customer:, organization:) }
  let(:invoice_subscription) { create(:invoice_subscription, subscription:, invoice:, from_datetime:, to_datetime:, timestamp:) }
  let(:subscription) { create(:subscription, customer:, plan:) }
  let(:from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
  let(:to_datetime) { DateTime.parse("2024-12-31T23:59:59") }
  let(:timestamp) { DateTime.parse("2025-01-01T10:00:00") }
  let(:customer) { create(:customer, organization:) }
  let(:plan) { create(:plan, organization:, interval: :yearly) }
  let(:organization) { create(:organization) }

  context "when plan has no minimum commitment" do
    context "when invoice has no commitment fee" do
      it "creates a commitment fee" do
        expect do
          service_call
        end.not_to change(Fee.commitment, :count)
      end
    end
  end

  context "when plan has a minimum commitment" do
    let(:commitment_fee) { Fee.commitment.first }

    before { create(:commitment, :minimum_commitment, plan:) }

    context "when invoice has no commitment fee" do
      context "when commitment has no taxes" do
        it "creates a commitment fee" do
          expect do
            service_call
          end.to change(Fee.commitment, :count).by(1)
        end

        it "saves taxes amount cents" do
          result = service_call
          expect(result).to be_success
          fee = result.fee

          expect(fee.taxes_amount_cents).to eq(0)
        end

        it "creates a fee" do
          result = service_call
          expect(result).to be_success
          fee = result.fee

          expect(fee).to have_attributes(
            id: String,
            organization_id: organization.id,
            billing_entity_id: customer.billing_entity_id,
            precise_amount_cents: 1000.0
          )
        end
      end

      context "when commitment has taxes" do
        let(:commitment_tax) { create(:tax) }
        let(:taxes_amount_cents) { (commitment_fee.amount_cents * commitment_tax.rate / 100.to_f).round }

        before do
          create(:commitment_applied_tax, commitment: plan.minimum_commitment, tax: commitment_tax)
        end

        it "creates a commitment fee" do
          expect do
            service_call
          end.to change(Fee.commitment, :count).by(1)
        end
      end
    end

    context "when invoice already has a minimum commitment fee for a subscription" do
      before { create(:minimum_commitment_fee, invoice:, subscription:) }

      it "does not create a commitment fee" do
        expect do
          service_call
        end.not_to change(Fee.commitment, :count)
      end
    end

    context "when invoice already has a minimum commitment fee for different subscription" do
      before { create(:minimum_commitment_fee, invoice:) }

      it "creates a commitment fee" do
        expect do
          service_call
        end.to change(Fee.commitment, :count).by(1)
      end
    end
  end
end
