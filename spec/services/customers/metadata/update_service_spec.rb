# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::Metadata::UpdateService do
  subject(:update_service) { described_class.new(customer:, params:) }

  before_all do
    create_default(:organization)
  end

  let_it_be(:customer) { create(:customer) }
  let(:customer_metadata) { create(:customer_metadata, customer:) }
  let(:another_customer_metadata) { create(:customer_metadata, customer:, key: "test", value: "1") }
  let(:params) do
    [
      {
        id: customer_metadata.id,
        key: "new key",
        value: "new value",
        display_in_invoice: true
      },
      {
        key: "Added key",
        value: "Added value",
        display_in_invoice: true
      }
    ]
  end

  describe "#call" do
    before do
      customer_metadata
      another_customer_metadata
    end

    it "updates existing metadata" do
      result = update_service.call

      metadata_keys = result.customer.metadata.pluck(:key)
      metadata_ids = result.customer.metadata.pluck(:id)

      expect(result.customer.metadata.count).to eq(2)
      expect(metadata_keys).to include("new key")
      expect(metadata_ids).to include(customer_metadata.id)
    end

    it "adds new metadata" do
      result = update_service.call

      metadata_keys = result.customer.metadata.pluck(:key)

      expect(result.customer.metadata.count).to eq(2)
      expect(metadata_keys).to include("Added key")
    end

    it "sanitizes not needed metadata" do
      result = update_service.call

      metadata_ids = result.customer.metadata.pluck(:id)

      expect(result.customer.metadata.count).to eq(2)
      expect(metadata_ids).not_to include(another_customer_metadata.id)
    end

    context "when the model refuses an entry" do
      let(:params) { [{id: customer_metadata.id, key: "new key", value: "new value"}, {key: "new key", value: "a" * 101}] }

      it "raises its errors, under the path of the entry for native v2" do
        expect { update_service.call }.to raise_error(BaseService::FailedResult) do |error|
          expect(error.result.error.messages).to eq(key: ["value_already_exist"], value: ["value_is_too_long"])
          expect(error.result.error.codes).to eq("metadata[1].key": ["value_already_exist"], "metadata[1].value": ["value_is_too_long"])
          expect(error.result.error.meta).to eq("metadata[1].value": {max_length: 100})
        end
      end
    end
  end
end
