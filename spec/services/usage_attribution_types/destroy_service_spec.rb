# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributionTypes::DestroyService do
  subject(:result) { described_class.call(usage_attribution_type:) }

  let(:organization) { create(:organization) }
  let(:usage_attribution_type) { create(:usage_attribution_type, organization:) }

  it "discards the usage attribution type" do
    expect { result }.to change { usage_attribution_type.reload.discarded? }.from(false).to(true)

    expect(result).to be_success
    expect(result.usage_attribution_type).to eq(usage_attribution_type)
  end

  it "does not hard delete the record" do
    usage_attribution_type

    expect { result }.not_to change(UsageAttributionType.with_discarded, :count)
  end

  context "when the type has values" do
    let(:customer) { create(:customer, organization:) }
    let!(:value) { create(:usage_attribution_value, organization:, customer:, usage_attribution_type:) }

    it "discards the values too" do
      expect { result }.to change { value.reload.discarded? }.from(false).to(true)
      expect(result).to be_success
    end
  end

  context "when values of a child type are placed under the type's values" do
    let(:customer) { create(:customer, organization:) }
    let(:child) { create(:usage_attribution_type, organization:, parent: usage_attribution_type) }
    let(:parent_value) { create(:usage_attribution_value, organization:, customer:, usage_attribution_type:) }
    let(:other_parent_value) { create(:usage_attribution_value, organization:, customer:) }
    let(:child_value) { create(:usage_attribution_value, organization:, customer:, usage_attribution_type: child, parent: parent_value) }
    let(:discarded_child_value) { create(:usage_attribution_value, organization:, customer:, usage_attribution_type: child, parent: parent_value, deleted_at: Time.current) }
    let(:other_child_value) { create(:usage_attribution_value, organization:, customer:, usage_attribution_type: child, parent: other_parent_value) }

    before { [child_value, discarded_child_value, other_child_value] }

    it "makes them roots" do
      result

      expect(child_value.reload.parent_id).to be_nil
      expect(UsageAttributionValue.with_discarded.find(discarded_child_value.id).parent_id).to be_nil
      expect(other_child_value.reload.parent_id).to eq(other_parent_value.id)
    end
  end

  context "when the type has child types" do
    let!(:child) { create(:usage_attribution_type, organization:, parent: usage_attribution_type) }

    it "discards the type" do
      expect { result }.to change { usage_attribution_type.reload.discarded? }.from(false).to(true)
      expect(result).to be_success
    end

    it "keeps the children" do
      expect { result }.not_to change { child.reload.discarded? }
    end

    it "leaves the child able to resolve its discarded parent" do
      result

      expect(child.reload.parent_id).to eq(usage_attribution_type.id)
      expect(child.parent).to eq(usage_attribution_type)
      expect(child.parent).to be_discarded
    end
  end

  context "when usage_attribution_type is nil" do
    let(:usage_attribution_type) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("usage_attribution_type")
    end
  end
end
