# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Quotes::Approve do
  let(:required_permission) { "quotes:approve" }
  let(:membership) { create(:membership) }
  let(:customer) { create(:customer, organization: membership.organization) }
  let(:quote) { create(:quote, organization: membership.organization, customer:) }

  let(:input) do
    {
      id: quote.id
    }
  end

  let(:mutation) do
    <<-GQL
      mutation($input: ApproveQuoteInput!) {
        approveQuote(input: $input) {
          id,
          customer { id },
          organization { id },
          number,
          version,
          status,
          approvedAt
        }
      }
    GQL
  end

  before do
    membership.organization.enable_feature_flag!(:order_forms)
    quote
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "quotes:approve"

  context "with valid input", :premium do
    it "approves a quote" do
      freeze_time do
        result = execute_graphql(
          current_user: membership.user,
          current_organization: membership.organization,
          permissions: required_permission,
          query: mutation,
          variables: {input:}
        )

        expect(result["data"]["approveQuote"]).to include(
          "id" => quote.id,
          "customer" => {"id" => customer.id},
          "organization" => {"id" => membership.organization.id},
          "number" => quote.number,
          "version" => quote.version,
          "status" => "approved",
          "approvedAt" => Time.current.iso8601
        )
      end
    end
  end
end
