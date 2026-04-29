# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::QuoteVersions::Clone do
  let(:required_permission) { "quotes:clone" }
  let(:membership) { create(:membership) }
  let(:quote_version) { create(:quote_version, organization: membership.organization) }

  let(:input) do
    {
      id: quote_version.id
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: CloneQuoteVersionInput!) {
        cloneQuoteVersion(input: $input) {
          id,
          organization { id },
          version,
          status,
          shareToken,
          voidReason,
          voidedAt
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
  it_behaves_like "requires permission", "quotes:clone"

  context "with valid input", :premium do
    it "clones a quote" do
      freeze_time do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: membership.organization,
          permissions: required_permission,
          query: mutation,
          variables: {input:}
        )

        cloned = result["data"]["cloneQuoteVersion"]
        expect(cloned).to include(
          "organization" => {"id" => membership.organization.id},
          "version" => quote_version.version + 1,
          "status" => "draft",
          "voidReason" => nil,
          "voidedAt" => nil
        )
        expect(cloned["id"]).to be_present
        expect(cloned["id"]).not_to eq(quote_version.id)
        expect(cloned["shareToken"]).to be_present

        quote_version.reload
        expect(quote_version.voided?).to eq(true)
        expect(quote_version.void_reason).to eq("superseded")
        expect(quote_version.voided_at).to eq(Time.current)
        expect(quote_version.share_token).to eq(nil)
      end
    end
  end

  context "when quote version is not found", :premium do
    let(:input) { {id: "00000000-0000-0000-0000-000000000000"} }

    it "returns a not found error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {input:}
      )

      expect_not_found(result)
    end
  end

  context "when quote version is approved", :premium do
    let(:quote_version) { create(:quote_version, :approved, organization: membership.organization) }

    it "returns a not allowed error" do
      result = execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {input:}
      )

      expect_graphql_error(result:, message: "inappropriate_state")
    end
  end
end
