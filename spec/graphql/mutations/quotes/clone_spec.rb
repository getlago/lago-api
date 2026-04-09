# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Quotes::Clone do
  let(:required_permission) { "quotes:clone" }
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
      mutation($input: CloneQuoteInput!) {
        cloneQuote(input: $input) {
          id,
          customer { id },
          organization { id },
          number,
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
    quote
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

        cloned = result["data"]["cloneQuote"]
        expect(cloned).to include(
          "customer" => {"id" => customer.id},
          "organization" => {"id" => membership.organization.id},
          "number" => quote.number,
          "version" => quote.version + 1,
          "status" => "draft",
          "voidReason" => nil,
          "voidedAt" => nil
        )
        expect(cloned["id"]).to be_present
        expect(cloned["id"]).not_to eq(quote.id)
        expect(cloned["shareToken"]).to be_present

        quote.reload
        expect(quote.voided?).to eq(true)
        expect(quote.void_reason).to eq("superseded")
        expect(quote.voided_at).to eq(Time.current)
        expect(quote.share_token).to eq(nil)
      end
    end
  end
end
