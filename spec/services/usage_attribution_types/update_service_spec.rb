# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageAttributionTypes::UpdateService do
  subject(:result) { described_class.call(usage_attribution_type:, params:) }

  let(:organization) { create(:organization) }
  let(:usage_attribution_type) do
    create(
      :usage_attribution_type,
      organization:,
      code: "user",
      name: "User",
      description: "A person using the product",
      attribution_keys: ["user_id"]
    )
  end
  let(:params) { {name: "Member"} }

  it "updates the name" do
    expect(result).to be_success
    expect(result.usage_attribution_type.name).to eq("Member")
  end

  it "leaves untouched attributes alone" do
    expect(result.usage_attribution_type.code).to eq("user")
    expect(result.usage_attribution_type.description).to eq("A person using the product")
    expect(result.usage_attribution_type.attribution_keys).to eq(["user_id"])
    expect(result.usage_attribution_type.role).to eq("hierarchical")
  end

  context "when usage_attribution_type is nil" do
    let(:usage_attribution_type) { nil }

    it "returns a not found failure" do
      expect(result).not_to be_success
      expect(result.error.resource).to eq("usage_attribution_type")
    end
  end

  describe "description" do
    let(:params) { {description: "A member of a team"} }

    it "is updated" do
      expect(result).to be_success
      expect(result.usage_attribution_type.reload.description).to eq("A member of a team")
    end

    context "when it is cleared" do
      let(:params) { {description: nil} }

      it "removes the description" do
        expect(result).to be_success
        expect(result.usage_attribution_type.reload.description).to be_nil
      end
    end

    context "when usage has already been attributed" do
      before { create(:usage_attribution_value, organization:, usage_attribution_type:) }

      it "still updates the description" do
        expect(result).to be_success
        expect(result.usage_attribution_type.reload.description).to eq("A member of a team")
      end
    end
  end

  describe "attribution_keys" do
    let(:params) { {attribution_keys: ["  employee_id  "]} }

    it "is remapped and stripped" do
      expect(result).to be_success
      expect(result.usage_attribution_type.attribution_keys).to eq(["employee_id"])
    end

    it "accepts several keys for the same type" do
      params[:attribution_keys] = %w[user_id userId usr_id]

      expect(result).to be_success
      expect(result.usage_attribution_type.attribution_keys).to eq(%w[user_id userId usr_id])
    end

    context "when usage has already been attributed" do
      before { create(:usage_attribution_value, organization:, usage_attribution_type:) }

      it "still updates the keys" do
        expect(result).to be_success
        expect(result.usage_attribution_type.attribution_keys).to eq(["employee_id"])
      end
    end

    context "when a key is already claimed by another type" do
      before { create(:usage_attribution_type, organization:, code: "team", attribution_keys: ["employee_id"]) }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:attribution_keys]).to eq(["value_already_exist"])
      end
    end
  end

  describe "code" do
    let(:params) { {code: "  member  "} }

    it "is updated and stripped" do
      expect(result).to be_success
      expect(result.usage_attribution_type.code).to eq("member")
    end

    context "when usage has already been attributed" do
      before { create(:usage_attribution_value, organization:, usage_attribution_type:) }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:code]).to eq(["usage_already_attributed"])
      end
    end
  end

  describe "role" do
    let(:params) { {role: "flat"} }

    it "can be turned flat" do
      expect(result).to be_success
      expect(result.usage_attribution_type.role).to eq("flat")
    end

    context "when the type has children" do
      before { create(:usage_attribution_type, organization:, parent: usage_attribution_type) }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:role]).to eq(["cannot_be_flat_with_children"])
      end
    end

    context "when the type still has a parent" do
      let(:parent) { create(:usage_attribution_type, organization:, code: "department") }

      before { usage_attribution_type.update!(parent:) }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:parent_id]).to include("forbidden_for_flat_role")
      end
    end

    context "when the parent is cleared in the same call" do
      let(:parent) { create(:usage_attribution_type, organization:, code: "department") }
      let(:params) { {role: "flat", parent_id: nil} }

      before { usage_attribution_type.update!(parent:) }

      it "is allowed" do
        expect(result).to be_success
        expect(result.usage_attribution_type.role).to eq("flat")
        expect(result.usage_attribution_type.parent).to be_nil
      end
    end
  end

  describe "parent_id" do
    let(:parent) { create(:usage_attribution_type, organization:, code: "department") }
    let(:params) { {parent_id: parent.id} }

    it "re-parents the type" do
      expect(result).to be_success
      expect(result.usage_attribution_type.parent).to eq(parent)
    end

    context "when detaching the type" do
      let(:params) { {parent_id: nil} }

      before { usage_attribution_type.update!(parent:) }

      it "makes it a root" do
        expect(result).to be_success
        expect(result.usage_attribution_type.parent).to be_nil
      end
    end

    context "when the parent does not exist" do
      let(:params) { {parent_id: SecureRandom.uuid} }

      it "returns a not found failure" do
        expect(result).not_to be_success
        expect(result.error.resource).to eq("parent_usage_attribution_type")
      end
    end

    context "when the parent belongs to another organization" do
      let(:parent) { create(:usage_attribution_type, code: "department") }

      it "returns a not found failure" do
        expect(result).not_to be_success
        expect(result.error.resource).to eq("parent_usage_attribution_type")
      end
    end

    context "when the parent is a flat type" do
      let(:parent) { create(:flat_usage_attribution_type, organization:, code: "model") }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:parent_id]).to include("must_be_hierarchical")
      end
    end

    context "when the parent would form a cycle" do
      let(:child) { create(:usage_attribution_type, organization:, parent: usage_attribution_type) }
      let(:params) { {parent_id: child.id} }

      it "returns a validation failure" do
        expect(result).not_to be_success
        expect(result.error.messages[:parent_id]).to include("cannot_form_a_cycle")
      end
    end
  end

  context "when usage has already been attributed" do
    let(:parent) { create(:usage_attribution_type, organization:, code: "department") }
    let(:params) do
      {
        name: "Member",
        description: "A member of a team",
        code: "member",
        attribution_keys: ["employee_id"],
        role: "flat",
        parent_id: parent.id
      }
    end

    before { create(:usage_attribution_value, organization:, usage_attribution_type:) }

    it "returns a validation failure listing each frozen attribute" do
      expect(result).not_to be_success
      expect(result.error.messages).to eq(
        code: ["usage_already_attributed"],
        role: ["usage_already_attributed"],
        parent_id: ["usage_already_attributed"]
      )
    end

    it "does not persist anything" do
      expect { result }.not_to change { usage_attribution_type.reload.attributes }
    end

    context "when the frozen attributes are submitted unchanged" do
      let(:params) do
        {name: "Member", code: "user", attribution_keys: ["user_id"], role: "hierarchical", parent_id: nil}
      end

      it "updates the name" do
        expect(result).to be_success
        expect(result.usage_attribution_type.reload.name).to eq("Member")
      end
    end

    context "when only the name is submitted" do
      let(:params) { {name: "Member"} }

      it "updates the name" do
        expect(result).to be_success
        expect(result.usage_attribution_type.reload.name).to eq("Member")
      end
    end

    context "when every attributed value has been discarded" do
      before { usage_attribution_type.usage_attribution_values.sole.discard! }

      it "still returns a validation failure listing each frozen attribute" do
        expect(result).not_to be_success
        expect(result.error.messages).to eq(
          code: ["usage_already_attributed"],
          role: ["usage_already_attributed"],
          parent_id: ["usage_already_attributed"]
        )
      end

      context "when only the name is submitted" do
        let(:params) { {name: "Member"} }

        it "updates the name" do
          expect(result).to be_success
          expect(result.usage_attribution_type.reload.name).to eq("Member")
        end
      end
    end
  end

  context "when the code is already used by another type" do
    let(:params) { {code: "department"} }

    before { create(:usage_attribution_type, organization:, code: "department") }

    it "returns a validation failure" do
      expect(result).not_to be_success
      expect(result.error.messages[:code]).to include("value_already_exist")
    end
  end
end
