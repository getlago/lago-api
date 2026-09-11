# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributionTypes::CreateService do
  subject(:result) { described_class.call(organization:, params:) }

  let(:organization) { create(:organization) }
  let(:params) do
    {
      code: "user",
      name: "User",
      attribution_key: "user_id",
      role: "hierarchical"
    }
  end

  it "creates a usage attribution type" do
    expect { result }.to change(UsageAttributionType, :count).by(1)

    usage_attribution_type = result.usage_attribution_type
    expect(usage_attribution_type.organization).to eq(organization)
    expect(usage_attribution_type.code).to eq("user")
    expect(usage_attribution_type.name).to eq("User")
    expect(usage_attribution_type.attribution_key).to eq("user_id")
    expect(usage_attribution_type.role).to eq("hierarchical")
    expect(usage_attribution_type.parent).to be_nil
  end

  it "strips the code and the attribution key" do
    params[:code] = "  user  "
    params[:attribution_key] = "  user_id  "

    expect(result.usage_attribution_type.code).to eq("user")
    expect(result.usage_attribution_type.attribution_key).to eq("user_id")
  end

  context "when organization is nil" do
    let(:organization) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("organization")
    end
  end

  context "when a parent is given" do
    let(:parent) { create(:usage_attribution_type, organization:, code: "department") }

    before { params[:parent_id] = parent.id }

    it "attaches the parent" do
      expect(result).to be_success
      expect(result.usage_attribution_type.parent).to eq(parent)
    end
  end

  context "when the parent does not exist" do
    before { params[:parent_id] = SecureRandom.uuid }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("parent_usage_attribution_type")
    end
  end

  context "when the parent belongs to another organization" do
    let(:parent) { create(:usage_attribution_type, code: "department") }

    before { params[:parent_id] = parent.id }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("parent_usage_attribution_type")
    end
  end

  context "when the role is flat and a parent is given" do
    let(:parent) { create(:usage_attribution_type, organization:, code: "department") }

    before do
      params[:role] = "flat"
      params[:parent_id] = parent.id
    end

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:parent_id]).to include("forbidden_for_flat_role")
    end
  end

  context "when the parent is a flat type" do
    let(:parent) { create(:flat_usage_attribution_type, organization:, code: "model") }

    before { params[:parent_id] = parent.id }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:parent_id]).to include("must_be_hierarchical")
    end
  end

  context "when the role is not supported" do
    before { params[:role] = "unknown" }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:role]).to be_present
    end
  end

  context "when the code is already used" do
    before { create(:usage_attribution_type, organization:, code: "user") }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:code]).to include("value_already_exist")
    end
  end

  context "when the attribution key is already used" do
    before { create(:usage_attribution_type, organization:, attribution_key: "user_id") }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:attribution_key]).to include("value_already_exist")
    end
  end

  context "when the code is missing" do
    before { params[:code] = nil }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:code]).to be_present
    end
  end

  context "when the attribution key is missing" do
    before { params[:attribution_key] = nil }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:attribution_key]).to be_present
    end
  end
end
