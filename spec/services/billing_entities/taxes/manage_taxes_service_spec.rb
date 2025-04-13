# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntities::Taxes::ManageTaxesService do
  subject(:service) { described_class.new(billing_entity:, tax_codes:) }

  let(:organization) { create(:organization) }
  let(:billing_entity) { organization.default_billing_entity }
  let(:tax1) { create(:tax, organization:, code: "TAX_CODE_1") }
  let(:tax2) { create(:tax, organization:, code: "TAX_CODE_2") }

  
  describe "#call" do
    context "when sending tax codes" do
      let(:tax_codes) { ["TAX_CODE_1", "TAX_CODE_2"] }

      before do
        tax1
        tax2
      end

      it "applies taxes to the billing entity" do
        service.call

        expect(billing_entity.reload.taxes).to eq([tax1, tax2])
      end

      context "when some tax codes do not exist" do
        let(:tax_codes) { ["TAX_CODE_1", "TAX_CODE_3"] }

        it "returns a not_found_failure" do
          result = service.call
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.error_code).to eq("tax_not_found")
        end
      end

      context "when billing_entity had another tax applied" do
        let(:tax3) { create(:tax, organization:, code: "TAX_CODE_3") }
        before do
          billing_entity.taxes << tax3
        end

        it "removes the other tax and applies the new ones" do
          service.call

          expect(billing_entity.taxes).to eq([tax1, tax2])
        end
      end
      
      context "when tax codes contain duplicates" do
        let(:tax_codes) { ["TAX_CODE_1", "TAX_CODE_2", "TAX_CODE_1"] }
        
        it "applies each tax only once" do
          service.call
          
          expect(billing_entity.taxes).to eq([tax1, tax2])
        end
      end
      
      context "when tax codes have different case" do
        let(:tax_codes) { ["tax_code_1", "TAX_CODE_2"] }
        
        it "matches tax codes case-insensitively" do
          service.call
          
          expect(billing_entity.taxes).to eq([tax1, tax2])
        end
      end
    end

    context "when sending empty tax codes" do
      let(:tax_codes) { [] }

      before do
        billing_entity.taxes = [tax1, tax2]
      end


      it "removes taxes from the billing entity" do
        service.call

        expect(billing_entity.taxes).to be_empty
      end
    end
    
    context "when tax_codes is nil" do
      let(:tax_codes) { nil }
      
      before do
        billing_entity.taxes = [tax1, tax2]
      end
      
      it "removes taxes from the billing entity" do
        service.call
        
        expect(billing_entity.taxes).to be_empty
      end
    end
    
    context "when billing_entity is invalid" do
      let(:billing_entity) { nil }
      let(:tax_codes) { ["TAX_CODE_1"] }
      
      it "returns a not_found_failure" do
        result = service.call
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.error_code).to eq("billing_entity_not_found")
      end
    end
  end
end
