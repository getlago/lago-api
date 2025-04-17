# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::BillingEntitiesController, type: :request do
  let(:billing_entity1) { create(:billing_entity) }
  let(:organization) { billing_entity1.organization }
  let(:billing_entity2) { create(:billing_entity, organization:) }
  let(:billing_entity3) { create(:billing_entity) }
  let(:billing_entity4) { create(:billing_entity, :deleted, organization:) }
  let(:billing_entity5) { create(:billing_entity, :archived, organization:) }

  describe "GET /api/v1/billing_entities" do
    subject do
      get_with_token(organization, "/api/v1/billing_entities")
    end

    before do
      billing_entity1
      billing_entity2
      billing_entity3
      billing_entity4
      billing_entity5
    end

    it "returns a list of active not archived billing entities" do
      subject
      expect(response).to be_successful
      expect(json[:billing_entities].count).to eq(2)
      expect(json[:billing_entities].map { |billing_entity| billing_entity[:lago_id] }).to include(billing_entity1.id, billing_entity2.id)
    end
  end

  describe "GET /api/v1/billing_entities/:code" do
    subject do
      get_with_token(organization, "/api/v1/billing_entities/#{billing_entity1.code}")
    end

    it "returns a billing entity" do
      subject
      expect(response).to be_successful
      expect(json[:billing_entity][:lago_id]).to eq(billing_entity1.id)
    end

    context "when the billing entity has applied taxes" do
      let(:tax) { create(:tax) }
      let(:applied_tax) { create(:billing_entity_applied_tax, billing_entity: billing_entity1, tax:) }

      before { applied_tax }

      it "returns the billing entity with the applied taxes" do
        subject
        expect(json[:billing_entity][:taxes].count).to eq(1)
      end
    end

    context "when the billing entity from another organization is requested" do
      subject do
        get_with_token(organization, "/api/v1/billing_entities/#{billing_entity3.code}")
      end

      it "returns a 404" do
        subject
        expect(response).to be_not_found
      end
    end

    context "when the billing entity is archived" do
      subject do
        get_with_token(organization, "/api/v1/billing_entities/#{billing_entity5.code}")
      end

      it "returns billing entity" do
        subject
        expect(response).to be_successful
        expect(json[:billing_entity][:lago_id]).to eq(billing_entity5.id)
      end
    end

    context "when the billing entity is deleted" do
      subject do
        get_with_token(organization, "/api/v1/billing_entities/#{billing_entity4.code}")
      end

      it "returns a 404" do
        subject
        expect(response).to be_not_found
      end
    end
  end
end
