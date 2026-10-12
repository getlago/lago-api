# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::Taxes::Object do
  subject(:graphql_type) { described_class }

  it do
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:organization).of_type("Organization")
    expect(subject).to have_field(:code).of_type("String!")
    expect(subject).to have_field(:description).of_type("String")
    expect(subject).to have_field(:name).of_type("String!")
    expect(subject).to have_field(:rate).of_type("Float!")
    expect(subject).to have_field(:applied_to_organization).of_type("Boolean!")
    expect(subject).to have_field(:applied_to_billing_entities_codes).of_type("[String!]!")
    expect(subject).to have_field(:created_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:updated_at).of_type("ISO8601DateTime!")
    expect(subject).to have_field(:add_ons_count).of_type("Int!")
    expect(subject).to have_field(:charges_count).of_type("Int!")
    expect(subject).to have_field(:customers_count).of_type("Int!")
    expect(subject).to have_field(:plans_count).of_type("Int!")
    expect(subject).to have_field(:auto_generated).of_type("Boolean!")
    expect(subject).to have_field(:integration_mappings).of_type("[Mapping!]")
  end

  describe "#integration_mappings" do
    let(:required_permission) { "organization:taxes:view" }
    let(:membership) { create(:membership) }
    let(:organization) { membership.organization }
    let(:tax) { create(:tax, organization:) }
    let(:netsuite_integration) { create(:netsuite_integration, organization:) }
    let(:xero_integration) { create(:xero_integration, organization:) }
    let(:netsuite_mapping) { create(:netsuite_mapping, integration: netsuite_integration, mappable: tax, organization:) }
    let(:xero_mapping) { create(:xero_mapping, integration: xero_integration, mappable: tax, organization:) }
    let(:integration_id) { nil }

    let(:query) do
      <<~GQL
        query($taxId: ID!, $integrationId: ID) {
          tax(id: $taxId) {
            integrationMappings(integrationId: $integrationId) { id }
          }
        }
      GQL
    end

    before do
      netsuite_mapping
      xero_mapping
    end

    def execute
      execute_graphql(
        current_user: membership.user,
        current_organization: organization,
        permissions: required_permission,
        query:,
        variables: {taxId: tax.id, integrationId: integration_id}
      ).dig("data", "tax", "integrationMappings")
    end

    context "without the integrationId argument" do
      it "returns all the mappings of the tax" do
        expect(execute.map { |mapping| mapping["id"] }).to match_array([netsuite_mapping.id, xero_mapping.id])
      end
    end

    context "with the integrationId argument" do
      let(:integration_id) { xero_integration.id }

      it "returns only the mappings of the given integration" do
        expect(execute.map { |mapping| mapping["id"] }).to eq([xero_mapping.id])
      end
    end
  end
end
