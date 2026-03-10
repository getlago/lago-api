# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrderForms::CloneService do
  subject(:clone_service) { described_class.new(order_form:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:order_form) do
    create(
      :order_form,
      organization:,
      customer:,
      status: "published"
    )
  end
  let(:catalog_reference) do
    create(
      :catalog_reference,
      order_form:,
      organization:
    )
  end

  describe ".call" do
    let(:result) { clone_service.call }

    context "when the order form is clonable", :premium do
      it "creates an clone, voids the original order form and copies all associated catalog references" do
        expect(result).to be_success
        cloned = result.order_form
        expect(cloned.id).not_to eq(order_form.id)
        expect(cloned.organization.id).to eq(order_form.organization.id)
        expect(cloned.customer.id).to eq(order_form.customer.id)
        expect(cloned.sequential_id).to eq(order_form.sequential_id)
        expect(cloned.version).to eq(order_form.version + 1)
        expect(cloned.number).to eq(order_form.number)
        expect(cloned.draft?).to eq(true)

        order_form.reload
        expect(order_form.voided?).to eq(true)
        expect(order_form.void_reason).to eq("superseded")

        cloned.reload
        cloned_catalog_references = cloned.catalog_references.pluck(:referenced_type, :referenced_id)
        original_catalog_references = order_form.catalog_references.pluck(:referenced_type, :referenced_id)
        expect(cloned_catalog_references).to match_array(original_catalog_references)
      end
    end

    context "when the order form is not clonable", :premium do
      before { order_form.signed! }

      it "does not create a clone" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ValidationFailure)
        expect(result.error.messages[:order_form]).to eq(["cloning_disallowed"])

        order_form.reload
        expect(order_form.signed?).to eq(true)
        expect(order_form.void_reason).to eq(nil)
      end
    end

    context "when license is not premium" do
      it "returns forbidden status" do
        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("feature_unavailable")
      end
    end
  end
end
