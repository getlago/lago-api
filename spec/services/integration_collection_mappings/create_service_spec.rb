# frozen_string_literal: true

require "rails_helper"

RSpec.describe IntegrationCollectionMappings::CreateService do
  let(:integration) { create(:netsuite_integration, organization:) }
  let(:organization) { membership.organization }
  let(:membership) { create(:membership) }
  let(:add_on) { create(:add_on, organization:) }

  describe "#call" do
    subject(:service_call) { described_class.call(params: create_args) }

    let(:create_args) do
      {
        mapping_type: :fallback_item,
        integration_id: integration.id,
        tax_nexus: "123",
        tax_code: "456",
        tax_type: "tax-type-1"
      }
    end

    context "without validation errors" do
      it "creates an integration" do
        expect { service_call }.to change(IntegrationCollectionMappings::NetsuiteCollectionMapping, :count).by(1)

        integration_collection_mapping =
          IntegrationCollectionMappings::NetsuiteCollectionMapping.order(:created_at).last

        aggregate_failures do
          expect(integration_collection_mapping.organization).to eq(organization)
          expect(integration_collection_mapping.mapping_type).to eq("fallback_item")
          expect(integration_collection_mapping.integration_id).to eq(integration.id)
          expect(integration_collection_mapping.tax_nexus).to eq(create_args[:tax_nexus])
          expect(integration_collection_mapping.tax_code).to eq(create_args[:tax_code])
          expect(integration_collection_mapping.tax_type).to eq(create_args[:tax_type])
        end
      end

      it "returns an integration collection mapping in result object" do
        result = service_call

        expect(result.integration_collection_mapping).to be_a(IntegrationCollectionMappings::NetsuiteCollectionMapping)
      end
    end

    context "with validation error" do
      let(:create_args) do
        {
          mappable_type: "AddOn",
          mappable_id: add_on.id
        }
      end

      it "returns an error" do
        result = service_call

        aggregate_failures do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.message).to eq("integration_not_found")
        end
      end
    end
  end
end
