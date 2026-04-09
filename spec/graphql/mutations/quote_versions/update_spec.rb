# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::QuoteVersions::Update do
  let(:required_permission) { "quotes:update" }
  let(:membership) { create(:membership) }
  let(:quote_version) { create(:quote_version, organization: membership.organization) }

  let(:input) do
    {
      id: quote_version.id,
      billingItems: {},
      content: "Test content"
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: UpdateQuoteVersionInput!) {
        updateQuoteVersion(input: $input) {
          id,
          organization { id },
          version,
          status,
          billingItems,
          content
        }
      }
    GQL
  end

  before do
    membership.organization.enable_feature_flag!(:order_forms)
    quote_version
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "quotes:update"

  context "with valid input", :premium do
    let!(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {input:}
      )
    end

    it "updates a quote version" do
      expect(result["data"]["updateQuoteVersion"]).to include(
        "id" => quote_version.id,
        "organization" => {"id" => membership.organization.id},
        "version" => quote_version.version,
        "status" => quote_version.status,
        "billingItems" => {},
        "content" => "Test content"
      )
    end
  end
end
