# frozen_string_literal: true

require "rails_helper"

RSpec.describe Resolvers::CopyToProductionPreviewResolver do
  subject(:execution) do
    execute_graphql(
      current_user: user,
      current_organization: organization,
      permissions: required_permission,
      query:,
      variables: {itemType: "billable_metric", id: metric.id}
    )
  end

  let(:required_permission) { "copy_to_production:create" }
  let(:production) { create(:organization) }
  let(:sandbox) { create(:organization, :sandbox, production_organization: production) }
  let(:organization) { sandbox }
  let(:user) { create(:user) }
  let(:membership) { create(:membership, user:, organization:, roles: %i[admin]) }
  let(:metric) { create(:billable_metric, organization: sandbox, code: "api_calls", name: "API calls") }

  let(:query) do
    <<~GQL
      query($itemType: CopyToProductionItemTypeEnum!, $id: ID!) {
        copyToProductionPreview(itemType: $itemType, id: $id) {
          blockingReason
          copiedItems { id itemType code name }
          reusedItems { id itemType code name }
          missingParent { id }
        }
      }
    GQL
  end

  before { create(:membership, user:, organization: production, roles: %i[admin]) }

  it_behaves_like "requires current user"
  it_behaves_like "requires current organization"
  it_behaves_like "requires permission", "copy_to_production:create"

  it "previews the move" do
    expect(execution["data"]["copyToProductionPreview"]).to eq(
      "blockingReason" => nil,
      "copiedItems" => [{"id" => metric.id, "itemType" => "billable_metric", "code" => "api_calls", "name" => "API calls"}],
      "reusedItems" => [],
      "missingParent" => nil
    )
  end

  context "when production has a metric with the same code" do
    before { create(:billable_metric, organization: production, code: "api_calls") }

    it "answers the blocking reason" do
      expect(execution["data"]["copyToProductionPreview"]["blockingReason"]).to eq("value_already_exist")
    end
  end

  context "when the organization is a production" do
    let(:organization) { production }
    let(:membership) { production.memberships.find_by(user:) }

    it "returns a forbidden error" do
      expect_graphql_error(result: execution, message: "copy_to_production_sandbox_only")
    end
  end
end
