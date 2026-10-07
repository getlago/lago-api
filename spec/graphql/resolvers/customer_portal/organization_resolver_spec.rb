# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CustomerPortal::OrganizationResolver do
  subject(:result) do
    execute_graphql(
      customer_portal_user: customer,
      query:
    )
  end

  let(:query) do
    <<~GQL
      query {
        customerPortalOrganization {
          id
          name
          logoUrl
          billingConfiguration {
            id
            documentLocale
          }
          premiumIntegrations
        }
      }
    GQL
  end

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:data) { result["data"]["customerPortalOrganization"] }
  let(:logo) { Rack::Test::UploadedFile.new(Rails.root.join("spec/factories/images/logo.png"), "image/png") }

  it_behaves_like "requires a customer portal user"

  it "returns the customer portal organization" do
    expect(data["id"]).to eq(organization.id)
    expect(data["name"]).to eq(organization.name)
    expect(data["billingConfiguration"]["id"]).to eq("#{organization.id}-c0nf")
    expect(data["billingConfiguration"]["documentLocale"]).to eq("en")
    expect(data["premiumIntegrations"]).to eq([])
  end

  describe "logoUrl" do
    subject(:logo_url) { data["logoUrl"] }

    context "when the customer's billing entity has a logo" do
      let(:billing_entity) { create(:billing_entity, organization:, logo:) }
      let(:customer) { create(:customer, organization:, billing_entity:) }

      it "returns the customer billing entity logo" do
        expect(logo_url).to eq(billing_entity.logo_url)
      end
    end

    context "when only the organization has a logo" do
      let(:organization) { create(:organization, logo:) }

      it "returns the organization logo" do
        expect(logo_url).to eq(organization.logo_url)
      end
    end

    context "when neither the billing entity nor the organization has a logo" do
      it "returns nil" do
        expect(logo_url).to be_nil
      end
    end
  end
end
