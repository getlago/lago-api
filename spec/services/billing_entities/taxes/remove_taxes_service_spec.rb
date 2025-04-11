# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntities::Taxes::RemoveTaxesService do
  subject(:service) { described_class.new(billing_entity:, tax_codes:) }

  let(:organization) { create(:organization) }
  let(:billing_entity) { organization.default_billing_entity }
  let(:tax_codes) { ["TAX_CODE_1", "TAX_CODE_2"] }

  describe "#call" do
    context "when tax codes exist in the organization" do
      let(:tax1) { create(:tax, organization:, code: "TAX_CODE_1") }
      let(:tax2) { create(:tax, organization:, code: "TAX_CODE_2") }

      before do
        billing_entity.applied_taxes.create!(tax: tax1)
        billing_entity.applied_taxes.create!(tax: tax2)
      end

      it "removes the specified taxes from the billing entity" do
        expect { service.call }.to change(billing_entity.applied_taxes, :count).by(-2)
      end

      it "returns a successful result" do
        result = service.call
        expect(result).to be_success
      end

      context "when some taxes are not applied to the billing entity" do
        before do
          billing_entity.applied_taxes.where(tax: tax2).destroy_all
        end

        it "removes only the applied taxes" do
          expect { service.call }.to change(billing_entity.applied_taxes, :count).by(-1)
        end

        it "returns a successful result" do
          result = service.call
          expect(result).to be_success
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

      it "does not remove any applied taxes" do
        expect { service.call }.not_to change(billing_entity.applied_taxes, :count)
      end
    end

    context "when tax_codes is empty" do
      let(:tax_codes) { [] }

      it "returns a successful result" do
        result = service.call
        expect(result).to be_success
      end

      it "does not remove any applied taxes" do
        expect { service.call }.not_to change(billing_entity.applied_taxes, :count)
      end
    end

    context "when tax_codes is nil" do
      let(:tax_codes) { nil }

      it "returns a successful result" do
        result = service.call
        expect(result).to be_success
      end

      it "does not remove any applied taxes" do
        expect { service.call }.not_to change(billing_entity.applied_taxes, :count)
      end
    end
  end
end
