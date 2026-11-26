# frozen_string_literal: true

require "rails_helper"

RSpec.describe Types::IntegrationCustomers::Quickbooks do
  subject { described_class }

  it do
    expect(subject).to have_field(:category).of_type("IntegrationConnectionCategoryEnum")
    expect(subject).to have_field(:code).of_type("String")
    expect(subject).to have_field(:external_customer_id).of_type("String")
    expect(subject).to have_field(:id).of_type("ID!")
    expect(subject).to have_field(:integration_code).of_type("String")
    expect(subject).to have_field(:integration_id).of_type("ID")
    expect(subject).to have_field(:integration_type).of_type("IntegrationTypeEnum")
    expect(subject).to have_field(:is_default).of_type("Boolean!")
    expect(subject).to have_field(:sync_with_provider).of_type("Boolean")
  end

  it "is reachable from the schema through the integration customer union" do
    expect(LagoApiSchema.types["QuickbooksCustomer"]).to eq(described_class)
    expect(LagoApiSchema.types["IntegrationCustomer"].possible_types).to include(described_class)
  end

  it "exposes no other field" do
    expect(subject.fields.keys).to contain_exactly(
      "category", "code", "externalCustomerId", "id", "integrationCode", "integrationId",
      "integrationType", "isDefault", "syncWithProvider"
    )
  end
end
