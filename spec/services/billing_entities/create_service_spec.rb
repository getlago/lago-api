# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingEntities::CreateService, type: :service do
  subject(:result) { described_class.call(organization:, params:) }

  let(:organization) { create :organization }
  let(:params) do
    {
      name: "Billing Entity",
      code: "billing-entity"
    }
  end

  context "when lago freemium" do
    it "returns an error" do
      expect(result).to be_failure
      expect(result.error).to be_a(BaseService::ForbiddenFailure)
    end
  end

  context "when lago premium" do
    around { |test| lago_premium!(&test) }

    context "when no multi_entity premium feature is enabled" do
      it "returns an error" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
      end
    end

    context "when multi_entities_pro premium feature is enabled" do
      let(:organization) do
        create(:organization, premium_integrations: ["multi_entities_pro"])
      end

      it "creates a billing entity with default document_numbering" do
        expect(organization.billing_entities.count).to eq(1)
        expect(result).to be_success
        expect(result.billing_entity).to be_persisted
        expect(result.billing_entity.name).to eq("Billing Entity")
        expect(result.billing_entity.code).to eq("billing-entity")
        expect(result.billing_entity.document_numbering).to eq("per_customer")
      end

      context "when max billing entities limit is reached" do
        it "returns an error" do
          create(:billing_entity, organization:)

          expect(organization.billing_entities.count).to eq(2)
          expect(result).to be_failure
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
        end
      end
    end

    context "when multi_entities_enterprise premium feature is enabled" do
      let(:organization) do
        create(:organization, premium_integrations: ["multi_entities_enterprise"])
      end

      it "creates a billing entity" do
        create(:billing_entity, organization:)

        expect(organization.billing_entities.count).to eq(2)
        expect(result).to be_success
        expect(result.billing_entity).to be_persisted
        expect(result.billing_entity.name).to eq("Billing Entity")
      end

      context "when record is invalid" do
        let(:params) { {name: nil, code: nil} }

        it "returns an error" do
          expect(result).to be_failure
          expect(result.error).to be_a(BaseService::ValidationFailure)
        end
      end
    end
  end

  # Is it responsibility of organization builder or billing entity builder to set the code?
  context "when passing params without code" do
    let(:params) { {name: "Billing Entity"} }

    it "creates a billing entity with a code" do
      organization.billing_entities.last.discard!
      expect(result).to be_success
      expect(result.billing_entity.code).to eq("billing_entity")
    end
  end
end
