# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mutations::Taxes::Destroy do
  let(:membership) { create(:membership) }
  let(:organization) { membership.organization }
  let(:tax) { create(:tax, organization:) }

  let(:mutation) do
    <<-GQL
      mutation($input: DestroyTaxInput!) {
        destroyTax(input: $input) { id }
      }
    GQL
  end

  before { tax }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "organization:taxes:update"

  it "destroys a tax" do
    expect do
      execute_graphql(
        current_user: membership.user,
        current_organization: membership.organization,
        permissions: "organization:taxes:update",
        query: mutation,
        variables: {input: {id: tax.id}}
      )
    end.to change(Tax, :count).by(-1)
  end

  it "returns a forbidden error without the organization:taxes:update permission" do
    result = execute_graphql(
      current_user: membership.user,
      current_organization: membership.organization,
      permissions: [],
      query: mutation,
      variables: {input: {id: tax.id}}
    )

    expect(result["errors"].first["extensions"]["code"]).to eq("forbidden")
    expect(tax.reload.deleted_at).to be_nil
  end
end
