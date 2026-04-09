# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::QuoteVersions::Approve do
  let(:required_permission) { "quotes:approve" }
  let(:membership) { create(:membership) }
  let(:quote_version) { create(:quote_version, organization: membership.organization) }

  let(:input) do
    {
      id: quote_version.id
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: ApproveQuoteVersionInput!) {
        approveQuoteVersion(input: $input) {
          id,
          organization { id },
          version,
          status,
          approvedAt
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
  it_behaves_like "requires permission", "quotes:approve"

  context "with valid input", :premium do
    it "approves a quote version" do
      freeze_time do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: membership.organization,
          permissions: required_permission,
          query: mutation,
          variables: {input:}
        )

        expect(result["data"]["approveQuoteVersion"]).to include(
          "id" => quote_version.id,
          "organization" => {"id" => membership.organization.id},
          "version" => quote_version.version,
          "status" => "approved",
          "approvedAt" => Time.current.iso8601
        )
      end
    end
  end
end
