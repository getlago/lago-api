# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Quotes::Destroy do
  let(:required_permission) { "quotes:delete" }
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:quote) { create(:quote, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyQuoteInput!) {
        destroyQuote(input: $input) { id }
      }
    GQL
  end

  before do
    membership.organization.enable_feature_flag!(:order_forms)
    quote
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "quotes:delete"

  context "with valid input", :premium do
    it "deletes a quote" do
      result = execute_query(
        query: mutation,
        input: {id: quote.id}
      )

      data = result["data"]["destroyQuote"]
      expect(data["id"]).to eq(quote.id)
    end
  end
end
