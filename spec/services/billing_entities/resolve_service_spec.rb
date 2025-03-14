# frozen_string_literal: true

RSpec.describe BillingEntities::ResolveService do
  subject(:result) { described_class.call(organization:, billing_entity_code:) }

  let(:organization) { create(:organization) }

  context "when billing_entity_code is provided" do
    let(:billing_entity_code) { "123" }

    context "when billing entity is not found" do
      it "returns not found failure" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.error_code).to eq("billing_entity_not_found")
      end
    end

    context "when billing entity is found" do
      let(:billing_entity_1) { create(:billing_entity, organization:) }
      let(:billing_entity_2) { create(:billing_entity, organization:, code: billing_entity_code) }

      before do
        billing_entity_1
        billing_entity_2
      end

      it "returns billing entity" do
        expect(result).to be_success
        expect(result.billing_entity).to eq(billing_entity_2)
      end
    end
  end

  context "when billing_entity_code is not provided" do
    let(:billing_entity_code) { nil }

    context "when there is no active billing entity" do
      before do
        organization.billing_entities.first.update!(archived_at: Time.current)
      end

      it "returns not found failure" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.error_code).to eq("billing_entity_not_found")
      end
    end

    context "when there is one active billing entity" do
      let(:billing_entity) { create(:billing_entity, organization:) }

      before do
        organization.billing_entities.first.discard!
        billing_entity
      end

      it "returns billing entity" do
        expect(result).to be_success
        expect(result.billing_entity).to eq(billing_entity)
      end
    end

    context "when there are multiple active billing entities" do
      let(:billing_entities) { create_list(:billing_entity, 2, organization:) }

      before { billing_entities }

      it "returns not found failure" do
        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::NotFoundFailure)
        expect(result.error.error_code).to eq("billing_entity_not_found")
      end
    end
  end
end
