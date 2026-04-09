# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Quotes::Create do
  let(:required_permission) { "quotes:create" }
  let(:membership) { create(:membership) }
  let(:customer) { create(:customer, organization: membership.organization) }
  let(:input) do
    {
      customerId: customer.id,
      orderType: "one_off"
    }
  end
  let(:mutation) do
    <<-GQL
      mutation($input: CreateQuoteInput!) {
        createQuote(input: $input) {
          id,
          customer { id },
          organization { id },
          number,
          version,
          status,
          orderType
        }
      }
    GQL
  end

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "quotes:create"

  context "with valid input", :premium do
    before { membership.organization.enable_feature_flag!(:order_forms) }

    let!(:result) do
      execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: required_permission,
        query: mutation,
        variables: {input:}
      )
    end

    it "creates a quote" do
      expect(result["data"]["createQuote"]).to include(
        "id" => String,
        "customer" => {"id" => customer.id},
        "organization" => {"id" => membership.organization.id},
        "number" => String,
        "version" => 1,
        "status" => "draft",
        "orderType" => "one_off"
      )
    end
  end
end
