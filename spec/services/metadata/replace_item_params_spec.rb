# frozen_string_literal: true

require "rails_helper"

RSpec.describe Metadata::ReplaceItemParams do
  subject(:result) { service_class.call(owner:, metadata:) }

  let(:service_class) do
    Class.new(BaseService) do
      include Metadata::ReplaceItemParams

      def initialize(owner:, metadata:)
        @owner = owner
        @metadata = metadata
        super()
      end

      def call
        return result.single_validation_failure!(field: :metadata, error_code: "invalid_shape") if malformed_metadata?(@metadata)

        replace_metadata!(@owner, @metadata)
        result
      rescue BaseService::FailedResult => e
        result.fail_with_error!(e.result.error)
      end
    end
  end

  let(:owner) { create(:catalog_plan) }
  let(:metadata) { {tier: "silver"} }
  let(:stored_metadata) { {"crm_id" => "123"} }

  before { create(:item_metadata, owner:, organization: owner.organization, value: stored_metadata) if stored_metadata }

  it "replaces the metadata with string keys" do
    expect(result).to be_success
    expect(owner.reload.metadata.value).to eq("tier" => "silver")
  end

  context "with an empty object" do
    let(:metadata) { {} }

    it "stores an empty object" do
      expect(result).to be_success
      expect(owner.reload.metadata.value).to eq({})
    end
  end

  context "with null" do
    let(:metadata) { nil }

    it "removes the metadata" do
      expect(result).to be_success
      expect(owner.reload.metadata).to be_nil
    end
  end

  context "with an owner without metadata" do
    let(:owner) { create(:plan_wallet) }
    let(:stored_metadata) { nil }

    it "creates it" do
      expect(result).to be_success
      expect(owner.reload.metadata).to have_attributes(organization_id: owner.organization_id, value: {"tier" => "silver"})
    end
  end

  [["a string", "abc"], ["an array", %w[crm_id 123]], ["false", false]].each do |description, value|
    context "with #{description}" do
      let(:metadata) { value }

      it "is malformed and leaves the metadata untouched" do
        expect(result.error.messages).to eq(metadata: ["invalid_shape"])
        expect(owner.reload.metadata.value).to eq("crm_id" => "123")
      end
    end
  end

  context "with content the metadata limits refuse" do
    let(:metadata) { {tier: 1} }

    it "refuses it on metadata" do
      expect(result.error).to be_a(BaseService::ValidationFailure)
      expect(result.error.messages).to eq(metadata: ["value_is_invalid"])
      expect(owner.reload.metadata.value).to eq("crm_id" => "123")
    end
  end
end
