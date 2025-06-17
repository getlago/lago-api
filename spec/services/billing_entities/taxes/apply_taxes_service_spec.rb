# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntities::Taxes::ApplyTaxesService do
  subject(:service) { described_class.new(billing_entity:, tax_codes:) }

  let(:organization) { create(:organization) }
  let(:billing_entity) { organization.default_billing_entity }
  let(:tax_codes) { ["TAX_CODE_1", "TAX_CODE_2"] }

  describe "#call" do
    context "when tax codes exist in the organization" do
      let(:tax1) { create(:tax, organization:, code: "TAX_CODE_1") }
      let(:tax2) { create(:tax, organization:, code: "TAX_CODE_2") }

      before do
        tax1
        tax2
      end

      it "creates applied taxes for the billing entity" do
        expect { service.call }.to change(billing_entity.applied_taxes, :count).by(2)
        expect(billing_entity.applied_taxes.pluck(:tax_id)).to match_array([tax1.id, tax2.id])
      end

      context "when billing_entity already have taxes applied" do
        before do
          billing_entity.applied_taxes.create!(tax: tax1, organization:)
        end

        it "does not create duplicate applied taxes" do
          expect { service.call }.to change(billing_entity.applied_taxes, :count).by(1)
        end
      end

      context "when organization have invoices in multiple billing_entities" do
        let(:other_billing_entity) { create(:billing_entity, organization:) }
        let(:invoice1) { create(:invoice, organization:, billing_entity:) }
        let(:invoice2) { create(:invoice, :draft, organization:, billing_entity:) }
        let(:invoice3) { create(:invoice, :draft, organization:, billing_entity: other_billing_entity) }

        before do
          invoice1
          invoice2
          invoice3
        end

        it "sets to refresh draft invoice of this billing entity" do
          service.call
          expect(invoice1.reload.ready_to_be_refreshed).to be_falsey
          expect(invoice2.reload.ready_to_be_refreshed).to be_truthy
          expect(invoice3.reload.ready_to_be_refreshed).to be_falsey
        end
      end
    end

    context "when some tax codes do not exist in the organization" do
      let(:tax1) { create(:tax, organization:, code: "TAX_CODE_1") }

      before { tax1 }

      it "fails with a not_found_failure" do
        result = service.call
        expect(result).not_to be_success
        expect(result.error.message).to eq("tax_not_found")
      end

      it "does not create any applied taxes" do
        service.call
        expect(billing_entity.applied_taxes.pluck(:tax_id)).to eq([])
      end
    end

    context "when tax_codes is empty" do
      let(:tax_codes) { [] }

      it "returns a successful result with no applied taxes" do
        result = service.call
        expect(result).to be_success
      end

      it "does not create any applied taxes" do
        expect { service.call }.not_to change(billing_entity.applied_taxes, :count)
      end

      context "when organization have invoices in multiple billing_entities" do
        let(:other_billing_entity) { create(:billing_entity, organization:) }
        let(:invoice1) { create(:invoice, organization:, billing_entity:) }
        let(:invoice2) { create(:invoice, :draft, organization:, billing_entity:) }
        let(:invoice3) { create(:invoice, :draft, organization:, billing_entity: other_billing_entity) }

        before do
          invoice1
          invoice2
          invoice3
        end

        it "does not set any draft invoices to ready to be refreshed" do
          service.call
          expect(invoice1.reload.ready_to_be_refreshed).to be_falsey
          expect(invoice2.reload.ready_to_be_refreshed).to be_falsey
          expect(invoice3.reload.ready_to_be_refreshed).to be_falsey
        end
      end
    end

    context "when tax_codes is nil" do
      let(:tax_codes) { nil }

      it "returns a successful result with no applied taxes" do
        result = service.call
        expect(result).to be_success
      end

      it "does not create any applied taxes" do
        expect { service.call }.not_to change(billing_entity.applied_taxes, :count)
      end
    end
  end
end
