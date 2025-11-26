# frozen_string_literal: true

require "rails_helper"

RSpec.describe Metadata::UpdateItemService do
  subject(:service) { described_class.new(owner, value:, replace:, preview:) }

  let(:organization) { create(:organization) }
  let(:owner) { create(:credit_note, organization:) }
  let(:value) { nil }
  let(:replace) { false }
  let(:preview) { false }

  describe "#call" do
    context "when owner does not support metadata" do
      let(:owner) { create(:organization) }

      it "returns a failure" do
        result = service.call

        expect(result).to be_failure
        expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
        expect(result.error.code).to eq("metadata_not_supported")
      end
    end

    context "with value: nil, replace: false, no existing metadata" do
      let(:value) { nil }
      let(:replace) { false }

      it "does not create metadata" do
        expect { service.call }.not_to change(Metadata::ItemMetadata, :count)
        expect(owner.reload.metadata).to be_nil
      end
    end

    context "with value: nil, replace: false, existing metadata" do
      let(:value) { nil }
      let(:replace) { false }

      before do
        metadata = create(:item_metadata, owner:, organization:, value: {"foo" => "bar"})
        owner.update!(metadata_id: metadata.id)
        owner.reload
      end

      it "preserves existing metadata" do
        result = service.call

        expect(result).to be_success
        expect(owner.reload.metadata.value).to eq({"foo" => "bar"})
      end
    end

    context "with value: nil, replace: true, no existing metadata" do
      let(:value) { nil }
      let(:replace) { true }

      it "does not create metadata" do
        expect { service.call }.not_to change(Metadata::ItemMetadata, :count)
        expect(owner.reload.metadata).to be_nil
      end
    end

    context "with value: nil, replace: true, existing metadata" do
      let(:value) { nil }
      let(:replace) { true }
      let!(:existing_metadata) do
        create(:item_metadata, owner:, organization:, value: {"foo" => "bar"}).tap do |m|
          owner.update!(metadata_id: m.id)
          owner.reload
        end
      end

      it "deletes existing metadata" do
        result = service.call

        expect(result).to be_success
        expect(owner.reload.metadata).to be_nil
        expect(Metadata::ItemMetadata.find_by(id: existing_metadata.id)).to be_nil
      end
    end

    context "with value: {}, replace: false, no existing metadata" do
      let(:value) { {} }
      let(:replace) { false }

      it "does not create metadata" do
        expect { service.call }.not_to change(Metadata::ItemMetadata, :count)
        expect(owner.reload.metadata).to be_nil
      end
    end

    context "with value: {}, replace: false, existing metadata" do
      let(:value) { {} }
      let(:replace) { false }

      before do
        metadata = create(:item_metadata, owner:, organization:, value: {"foo" => "bar"})
        owner.update!(metadata_id: metadata.id)
        owner.reload
      end

      it "preserves existing metadata" do
        result = service.call

        expect(result).to be_success
        expect(owner.reload.metadata.value).to eq({"foo" => "bar"})
      end
    end

    context "with value: {}, replace: true, no existing metadata" do
      let(:value) { {} }
      let(:replace) { true }

      it "creates metadata with empty hash" do
        expect { service.call }.to change(Metadata::ItemMetadata, :count).by(1)
        expect(owner.reload.metadata.value).to eq({})
      end
    end

    context "with value: {}, replace: true, existing metadata" do
      let(:value) { {} }
      let(:replace) { true }

      before do
        metadata = create(:item_metadata, owner:, organization:, value: {"foo" => "bar"})
        owner.update!(metadata_id: metadata.id)
        owner.reload
      end

      it "replaces with empty hash" do
        result = service.call

        expect(result).to be_success
        expect(owner.reload.metadata.value).to eq({})
      end
    end

    context "with value: {foo: bar, baz: qux}, replace: false, no existing metadata" do
      let(:value) { {"foo" => "bar", "baz" => "qux"} }
      let(:replace) { false }

      it "creates metadata" do
        expect { service.call }.to change(Metadata::ItemMetadata, :count).by(1)

        metadata = owner.reload.metadata
        expect(metadata.value).to eq({"foo" => "bar", "baz" => "qux"})
        expect(metadata.organization_id).to eq(organization.id)
        expect(metadata.owner).to eq(owner)
      end
    end

    context "with value: {foo: bar, baz: qux}, replace: false, existing metadata" do
      let(:value) { {"foo" => "bar", "baz" => "qux"} }
      let(:replace) { false }

      before do
        metadata = create(:item_metadata, owner:, organization:, value: {"old" => "value"})
        owner.update!(metadata_id: metadata.id)
        owner.reload
      end

      it "merges metadata" do
        result = service.call

        expect(result).to be_success
        expect(owner.reload.metadata.value).to eq({"old" => "value", "foo" => "bar", "baz" => "qux"})
      end
    end

    context "with value: {foo: bar}, replace: true, no existing metadata" do
      let(:value) { {"foo" => "bar"} }
      let(:replace) { true }

      it "creates metadata" do
        expect { service.call }.to change(Metadata::ItemMetadata, :count).by(1)
        expect(owner.reload.metadata.value).to eq({"foo" => "bar"})
      end
    end

    context "with value: {foo: bar}, replace: true, existing metadata" do
      let(:value) { {"foo" => "bar"} }
      let(:replace) { true }

      before do
        metadata = create(:item_metadata, owner:, organization:, value: {"old" => "value"})
        owner.update!(metadata_id: metadata.id)
        owner.reload
      end

      it "replaces metadata" do
        result = service.call

        expect(result).to be_success
        expect(owner.reload.metadata.value).to eq({"foo" => "bar"})
      end
    end

    context "with metadata overwriting existing key" do
      let(:value) { {"foo" => "new"} }
      let(:replace) { false }

      before do
        metadata = create(:item_metadata, owner:, organization:, value: {"foo" => "old"})
        owner.update!(metadata_id: metadata.id)
        owner.reload
      end

      it "overwrites the key" do
        result = service.call

        expect(result).to be_success
        expect(owner.reload.metadata.value).to eq({"foo" => "new"})
      end
    end

    context "with value: {foo: nil}, no existing metadata" do
      let(:value) { {"foo" => nil} }
      let(:replace) { false }

      it "creates metadata with nil value" do
        result = service.call

        expect(result).to be_success
        expect(owner.reload.metadata.value).to eq({"foo" => nil})
      end
    end

    context "with value: {foo: nil}, existing metadata" do
      let(:value) { {"foo" => nil} }
      let(:replace) { false }

      before do
        metadata = create(:item_metadata, owner:, organization:, value: {"foo" => "bar"})
        owner.update!(metadata_id: metadata.id)
        owner.reload
      end

      it "sets key to nil" do
        result = service.call

        expect(result).to be_success
        expect(owner.reload.metadata.value).to eq({"foo" => nil})
      end
    end

    context "with value: {foo: ''}, no existing metadata" do
      let(:value) { {"foo" => ""} }
      let(:replace) { false }

      it "creates metadata with empty string" do
        result = service.call

        expect(result).to be_success
        expect(owner.reload.metadata.value).to eq({"foo" => ""})
      end
    end

    context "with value: {foo: ''}, existing metadata" do
      let(:value) { {"foo" => ""} }
      let(:replace) { false }

      before do
        metadata = create(:item_metadata, owner:, organization:, value: {"foo" => "old", "bar" => "keep"})
        owner.update!(metadata_id: metadata.id)
        owner.reload
      end

      it "merges with empty string" do
        result = service.call

        expect(result).to be_success
        expect(owner.reload.metadata.value).to eq({"foo" => "", "bar" => "keep"})
      end
    end
  end

  describe "preview mode" do
    let(:preview) { true }
    let(:value) { {"foo" => "bar"} }
    let(:replace) { true }

    it "does not persist owner" do
      owner.reason = :other
      service.call

      expect(owner).to be_changed
    end

    context "with value: {foo: bar}, no existing metadata" do
      let(:value) { {"foo" => "bar"} }
      let(:replace) { true }

      it "does not persist metadata" do
        expect { service.call }.not_to change(Metadata::ItemMetadata, :count)
      end

      it "builds metadata in memory" do
        result = service.call

        expect(result).to be_success
        expect(owner.metadata).to be_present
        expect(owner.metadata).to be_new_record
        expect(owner.metadata.value).to eq({"foo" => "bar"})
        expect(owner.metadata_id).to eq(owner.metadata.id)
      end
    end

    context "with value: {foo: bar}, existing metadata" do
      let(:value) { {"foo" => "new"} }
      let(:replace) { true }

      before do
        metadata = create(:item_metadata, owner:, organization:, value: {"foo" => "old"})
        owner.update!(metadata_id: metadata.id)
        owner.reload
      end

      it "does not persist changes" do
        service.call

        expect(owner.metadata.value).to eq({"foo" => "new"})
        expect(owner.reload.metadata.value).to eq({"foo" => "old"})
      end
    end

    context "with merge, existing metadata" do
      let(:value) { {"bar" => "qux"} }
      let(:replace) { false }

      before do
        metadata = create(:item_metadata, owner:, organization:, value: {"foo" => "baz"})
        owner.update!(metadata_id: metadata.id)
        owner.reload
      end

      it "merges in memory without persisting" do
        result = service.call

        expect(result).to be_success
        expect(owner.metadata.value).to eq({"foo" => "baz", "bar" => "qux"})
        expect(owner.reload.metadata.value).to eq({"foo" => "baz"})
      end
    end

    context "with delete, existing metadata" do
      let(:value) { nil }
      let(:replace) { true }
      let!(:existing_metadata) do
        create(:item_metadata, owner:, organization:, value: {"foo" => "bar"}).tap do |m|
          owner.update!(metadata_id: m.id)
          owner.reload
        end
      end

      it "sets metadata_id to nil in memory without deleting" do
        result = service.call

        expect(result).to be_success
        expect(owner.metadata_id).to be_nil
        expect(Metadata::ItemMetadata.find_by(id: existing_metadata.id)).to be_present
      end
    end

    context "when owner has no id" do
      let(:owner) { CreditNote.new(organization:, customer: create(:customer, organization:), invoice: create(:invoice, organization:)) }
      let(:value) { {"foo" => "bar"} }
      let(:replace) { true }

      it "assigns id to owner without persisting" do
        expect(owner.id).to be_nil

        result = service.call

        expect(result).to be_success
        expect(owner.id).to be_present
        expect(owner).to be_new_record
        expect(owner.metadata).to be_present
        expect(owner.metadata).to be_new_record
      end
    end
  end
end
