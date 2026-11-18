# frozen_string_literal: true

require "rails_helper"

RSpec.describe Webhooks::ContractEntitlements::CreatedService do
  subject(:webhook_service) { described_class.new(object: contract, options: {contract_entitlement: render}) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:contract) { create(:contract, organization:, customer:, external_id: "contract_123") }
  let(:product_catalog_enabled) { true }
  # The render of the entitlement the write added, as the contract entitlement update service passes it.
  let(:render) do
    {
      contract_external_id: "contract_123",
      lago_contract_id: contract.id,
      feature_code: "storage",
      source: "contract",
      values: [{privilege_code: "limit", value: 10, plan_value: nil, source: "contract"}]
    }
  end

  before { allow(organization).to receive(:product_catalog_enabled?).and_return(product_catalog_enabled) }

  describe ".call" do
    it "creates a webhook on the contract with the rendered contract entitlement" do
      webhook_service.call

      webhook = Webhook.order(created_at: :desc).first
      expect(webhook.payload).to eq(
        "webhook_type" => "contract_entitlement.created",
        "object_type" => "contract_entitlement",
        "organization_id" => organization.id,
        "contract_entitlement" => {
          "contract_external_id" => "contract_123",
          "lago_contract_id" => contract.id,
          "feature_code" => "storage",
          "source" => "contract",
          "values" => [{"privilege_code" => "limit", "value" => 10, "plan_value" => nil, "source" => "contract"}]
        }
      )
      expect(webhook).to have_attributes(object_id: contract.id, object_type: "Contract")
    end

    context "when the organization does not have the product catalog" do
      let(:product_catalog_enabled) { false }

      it "does not create a webhook" do
        expect { webhook_service.call }.not_to change(Webhook, :count)
      end
    end
  end
end
